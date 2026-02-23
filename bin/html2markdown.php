#!/usr/bin/env php
<?php
/**
 * html2markdown.php — Core HTML-to-Markdown converter for markdown-for-agents.
 *
 * Reads HTML from stdin, strips non-content elements, converts to Markdown,
 * appends token estimate metadata, and writes to stdout.
 *
 * On any failure, outputs the original HTML unchanged (never break the response).
 */

declare(strict_types=1);

set_time_limit(5);
error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

// Autoload league/html-to-markdown
$autoloadPaths = [
    __DIR__ . '/../vendor/autoload.php',
    '/opt/markdown-for-agents/vendor/autoload.php',
];

$autoloaded = false;
foreach ($autoloadPaths as $path) {
    if (file_exists($path)) {
        require $path;
        $autoloaded = true;
        break;
    }
}

if (!$autoloaded) {
    fwrite(STDERR, "markdown-for-agents: autoload not found\n");
    // Pass through original input
    fpassthru(STDIN);
    exit(0);
}

use League\HTMLToMarkdown\HtmlConverter;
use League\HTMLToMarkdown\Converter\TableConverter;
use League\HTMLToMarkdown\Converter\ConverterInterface;
use League\HTMLToMarkdown\ElementInterface;

/**
 * Converts <s>, <del>, <strike> to ~~strikethrough~~.
 */
class StrikethroughConverter implements ConverterInterface
{
    public function convert(ElementInterface $element): string
    {
        $value = $element->getValue();
        if (!trim($value)) {
            return $value;
        }
        return '~~' . trim($value) . '~~';
    }

    public function getSupportedTags(): array
    {
        return ['s', 'del', 'strike'];
    }
}

/**
 * Converts <figure> to its inner content with surrounding blank lines,
 * and <figcaption> to italic text on its own line.
 */
class FigureConverter implements ConverterInterface
{
    public function convert(ElementInterface $element): string
    {
        $tag = $element->getTagName();
        $value = trim($element->getValue());
        if ($tag === 'figcaption') {
            return $value ? "\n*" . $value . "*" : '';
        }
        // <figure>: ensure block spacing
        return "\n\n" . $value . "\n\n";
    }

    public function getSupportedTags(): array
    {
        return ['figure', 'figcaption'];
    }
}

// Read all of stdin
$html = file_get_contents('php://stdin');

// Guard: empty input
if ($html === false || $html === '') {
    exit(0);
}

// Guard: oversized (>10MB) — pass through unchanged
$maxSize = 10 * 1024 * 1024;
if (strlen($html) > $maxSize) {
    echo $html;
    exit(0);
}

try {
    // Pre-clean: strip stray backslashes before quotes/entities in HTML
    // WordPress/some CMSes emit \&#8217; or \" in raw HTML output
    $html = preg_replace('/\\\\(&#\d+;)/', '$1', $html);
    $html = preg_replace('/\\\\(["\'])/', '$1', $html);

    // Load into DOMDocument
    $dom = new DOMDocument();

    // Suppress HTML parse warnings for malformed markup
    $previousUseErrors = libxml_use_internal_errors(true);
    $dom->loadHTML($html, LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD | LIBXML_NOERROR);
    libxml_clear_errors();
    libxml_use_internal_errors($previousUseErrors);

    $xpath = new DOMXPath($dom);

    // --- Content extraction strategy ---
    // Prefer semantic content containers over full-page stripping.
    // Priority: <article> → <main> → [role="main"] → fallback to body + strip
    $contentNode = null;
    $extractionMethod = 'fallback';

    // Try <article> first (most specific content container)
    $articles = $xpath->query('//article');
    if ($articles !== false && $articles->length === 1) {
        $contentNode = $articles->item(0);
        $extractionMethod = 'article';
    }

    // Try <main> if no single article found
    if ($contentNode === null) {
        $main = $xpath->query('//main')->item(0);
        if ($main !== null) {
            $contentNode = $main;
            $extractionMethod = 'main';
        }
    }

    // Try [role="main"]
    if ($contentNode === null) {
        $roleMain = $xpath->query('//*[@role="main"]')->item(0);
        if ($roleMain !== null) {
            $contentNode = $roleMain;
            $extractionMethod = 'role-main';
        }
    }

    if ($contentNode !== null) {
        // Semantic extraction: strip script/style within the content node,
        // then use its innerHTML directly
        $contentXpath = new DOMXPath($dom);
        foreach (['script', 'style', 'noscript', 'iframe'] as $tag) {
            $nodes = $contentXpath->query('.//' . $tag, $contentNode);
            if ($nodes !== false) {
                foreach (iterator_to_array($nodes) as $node) {
                    $node->parentNode->removeChild($node);
                }
            }
        }

        $cleanedHtml = '';
        foreach ($contentNode->childNodes as $child) {
            $cleanedHtml .= $dom->saveHTML($child);
        }
    } else {
        // Fallback: full-page stripping for pages without semantic markup

        // Strip non-content elements by tag name
        $stripTags = ['nav', 'header', 'footer', 'aside', 'script', 'style', 'noscript', 'iframe'];
        foreach ($stripTags as $tag) {
            $nodes = $xpath->query('//' . $tag);
            if ($nodes !== false) {
                foreach (iterator_to_array($nodes) as $node) {
                    $node->parentNode->removeChild($node);
                }
            }
        }

        // Strip elements by class containing non-content keywords
        $classKeywords = ['sidebar', 'widget', 'ad', 'advertisement', 'navigation', 'menu', 'breadcrumb'];
        foreach ($classKeywords as $keyword) {
            $query = '//*['
                . 'contains(concat(" ", normalize-space(@class), " "), " ' . $keyword . ' ")'
                . ' or contains(concat(" ", normalize-space(@class), " "), " ' . $keyword . '-")'
                . ' or contains(concat(" ", normalize-space(@class), "-"), "-' . $keyword . '-")'
                . ']';
            $nodes = $xpath->query($query);
            if ($nodes !== false) {
                foreach (iterator_to_array($nodes) as $node) {
                    $node->parentNode->removeChild($node);
                }
            }
        }

        // Strip elements by ARIA role
        $ariaRoles = ['navigation', 'banner', 'contentinfo', 'complementary'];
        foreach ($ariaRoles as $role) {
            $nodes = $xpath->query('//*[@role="' . $role . '"]');
            if ($nodes !== false) {
                foreach (iterator_to_array($nodes) as $node) {
                    $node->parentNode->removeChild($node);
                }
            }
        }

        // Strip skip-links
        $nodes = $xpath->query('//a[contains(concat(" ", normalize-space(@class), " "), " skip-link ") or contains(concat(" ", normalize-space(@class), " "), " screen-reader-text ")]');
        if ($nodes !== false) {
            foreach (iterator_to_array($nodes) as $node) {
                $node->parentNode->removeChild($node);
            }
        }

        // Strip scroll-to-top / back-to-top elements
        $nodes = $xpath->query('//*[contains(@class, "scroll-to-top") or contains(@class, "back-to-top") or contains(@class, "scrolltop") or contains(@id, "scroll-top") or contains(@id, "back-to-top")]');
        if ($nodes !== false) {
            foreach (iterator_to_array($nodes) as $node) {
                $node->parentNode->removeChild($node);
            }
        }

        // Extract body innerHTML
        $body = $xpath->query('//body')->item(0);
        if ($body !== null) {
            $cleanedHtml = '';
            foreach ($body->childNodes as $child) {
                $cleanedHtml .= $dom->saveHTML($child);
            }
        } else {
            $cleanedHtml = $dom->saveHTML();
        }
    }

    if ($cleanedHtml === false || trim($cleanedHtml) === '') {
        echo $html;
        exit(0);
    }

    $cleanedHtml = (string) $cleanedHtml;

    // Convert to Markdown
    $converter = new HtmlConverter([
        'header_style'    => 'atx',
        'hard_break'      => true,
        'strip_tags'      => true,
        'remove_nodes'    => 'head',
        'use_autolinks'   => true,
    ]);

    $converter->getEnvironment()->addConverter(new TableConverter());
    $converter->getEnvironment()->addConverter(new StrikethroughConverter());
    $converter->getEnvironment()->addConverter(new FigureConverter());

    $markdown = $converter->convert($cleanedHtml);

    // Clean up backslash-escaped quotes (WordPress/DOMDocument artifacts)
    $markdown = str_replace(['\\"', "\\'"], ['"', "'"], $markdown);
    // Remove spurious quotes around URLs in links/images: [text]("url") → [text](url)
    $markdown = preg_replace('/\("([^"]*?)"\)/', '($1)', $markdown);
    // Remove spurious quotes in image alt text: !["alt"](url) → ![alt](url)
    $markdown = preg_replace('/!\["([^"]*?)"\]/', '![$1]', $markdown);

    // Collapse excessive blank lines (3+ → 2)
    $markdown = preg_replace('/\n{3,}/', "\n\n", $markdown);

    // Trim trailing whitespace
    $markdown = rtrim($markdown) . "\n";

    // Estimate tokens: ~4 chars per token
    $tokenEstimate = (int) ceil(strlen($markdown) / 4);
    $htmlTokenEstimate = (int) ceil(strlen($html) / 4);
    $reduction = $htmlTokenEstimate > 0
        ? round((1 - $tokenEstimate / $htmlTokenEstimate) * 100)
        : 0;

    // Append metadata
    $markdown .= "\n<!-- mfa-meta:tokens={$tokenEstimate} html-tokens={$htmlTokenEstimate} reduction={$reduction}% extraction={$extractionMethod} -->\n";

    echo $markdown;

} catch (\Throwable $e) {
    // On any error, fall back to original HTML
    fwrite(STDERR, "markdown-for-agents: conversion error: " . $e->getMessage() . "\n");
    echo $html;
    exit(0);
}
