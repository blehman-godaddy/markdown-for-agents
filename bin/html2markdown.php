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
    // Load into DOMDocument
    $dom = new DOMDocument();

    // Suppress HTML parse warnings for malformed markup
    $previousUseErrors = libxml_use_internal_errors(true);
    $dom->loadHTML($html, LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD | LIBXML_NOERROR);
    libxml_clear_errors();
    libxml_use_internal_errors($previousUseErrors);

    $xpath = new DOMXPath($dom);

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
    // Match keyword as: standalone class ("ad"), hyphenated prefix ("ad-banner"),
    // or hyphenated suffix ("sidebar-widget"). Avoids false positives like
    // "has-global-padding" matching "ad".
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

    // Extract body innerHTML (strip <html>, <head>, <body> wrappers)
    $body = $xpath->query('//body')->item(0);
    if ($body !== null) {
        $cleanedHtml = '';
        foreach ($body->childNodes as $child) {
            $cleanedHtml .= $dom->saveHTML($child);
        }
    } else {
        $cleanedHtml = $dom->saveHTML();
    }

    if ($cleanedHtml === false || trim($cleanedHtml) === '') {
        // Fallback to original
        echo $html;
        exit(0);
    }

    // Also strip <head> content that may remain
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

    $markdown = $converter->convert($cleanedHtml);

    // Trim trailing whitespace
    $markdown = rtrim($markdown) . "\n";

    // Estimate tokens: ~4 chars per token
    $tokenEstimate = (int) ceil(strlen($markdown) / 4);

    // Append metadata
    $markdown .= "\n<!-- mfa-meta:tokens={$tokenEstimate} -->\n";

    echo $markdown;

} catch (\Throwable $e) {
    // On any error, fall back to original HTML
    fwrite(STDERR, "markdown-for-agents: conversion error: " . $e->getMessage() . "\n");
    echo $html;
    exit(0);
}
