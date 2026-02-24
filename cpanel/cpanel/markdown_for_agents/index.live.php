<?php
/**
 * index.live.php — cPanel customer page for markdown-for-agents.
 *
 * Allows customers to enable/disable HTML-to-Markdown conversion for their account.
 * Uses REMOTE_USER (set by cPanel, not spoofable) to identify the account.
 */

// cPanel sets REMOTE_USER for authenticated sessions
$username = $_ENV['REMOTE_USER'] ?? getenv('REMOTE_USER') ?: '';
if (empty($username)) {
    die('<p>Error: Could not determine your cPanel username.</p>');
}

// Security: ensure username matches expected format
if (!preg_match('/^[a-z][a-z0-9]{0,15}$/', $username)) {
    die('<p>Error: Invalid username format.</p>');
}

$scripts_dir = '/opt/markdown-for-agents/cpanel/scripts';

// --- Handle POST actions ---

$message = '';
$error   = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    if ($action === 'enable') {
        $ret = -1;
        $out = [];
        exec(sprintf('sudo %s/mfa-account-enable.sh %s 2>&1', $scripts_dir, escapeshellarg($username)), $out, $ret);
        if ($ret === 0) {
            $message = 'Markdown conversion enabled for your account.';
        } else {
            $error = 'Failed to enable markdown conversion. Please contact support.';
        }
    } elseif ($action === 'disable') {
        $ret = -1;
        $out = [];
        exec(sprintf('sudo %s/mfa-account-disable.sh %s 2>&1', $scripts_dir, escapeshellarg($username)), $out, $ret);
        if ($ret === 0) {
            $message = 'Markdown conversion disabled for your account.';
        } else {
            $error = 'Failed to disable markdown conversion. Please contact support.';
        }
    }
}

// --- Get current status ---

$status_cmd = sprintf('%s/mfa-account-status.sh %s 2>/dev/null', $scripts_dir, escapeshellarg($username));
$status_json = shell_exec($status_cmd);
$status = json_decode($status_json ?: '{}', true) ?: [];

$enabled          = $status['enabled'] ?? false;
$global_installed = $status['global_installed'] ?? false;
$version          = $status['version'] ?? 'unknown';
?>
<style>
    .mfa-wrap { max-width: 600px; }
    .mfa-status { padding: 15px; margin: 15px 0; border-radius: 6px; }
    .mfa-ok { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
    .mfa-warn { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; }
    .mfa-err { background: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
    .mfa-info { background: #d1ecf1; border: 1px solid #bee5eb; color: #0c5460; }
    .mfa-btn { display: inline-block; padding: 10px 24px; border-radius: 4px; text-decoration: none;
               font-size: 16px; cursor: pointer; border: none; color: white; margin: 10px 0; }
    .mfa-btn-enable { background: #28a745; }
    .mfa-btn-enable:hover { background: #218838; }
    .mfa-btn-disable { background: #dc3545; }
    .mfa-btn-disable:hover { background: #c82333; }
    .mfa-test { background: #f8f9fa; padding: 12px; border-radius: 6px; margin: 10px 0;
                font-family: monospace; font-size: 13px; overflow-x: auto; }
</style>

<div class="mfa-wrap">

<h1>Markdown for Agents</h1>
<p>Convert your site's HTML to Markdown automatically when AI agents request it.</p>

<?php if ($message): ?>
    <div class="mfa-status mfa-ok"><?= htmlspecialchars($message) ?></div>
<?php endif; ?>

<?php if ($error): ?>
    <div class="mfa-status mfa-err"><?= htmlspecialchars($error) ?></div>
<?php endif; ?>

<?php if (!$global_installed): ?>
    <div class="mfa-status mfa-warn">
        <strong>Not Available</strong> &mdash; The server administrator has not installed the markdown conversion infrastructure.
        Please contact your hosting provider.
    </div>
<?php else: ?>
    <?php if ($enabled): ?>
        <div class="mfa-status mfa-ok">
            <strong>Status: Enabled</strong><br>
            Your sites respond to <code>Accept: text/markdown</code> requests with Markdown content.
        </div>

        <form method="POST">
            <input type="hidden" name="action" value="disable">
            <button type="submit" class="mfa-btn mfa-btn-disable">Disable Markdown Conversion</button>
        </form>

        <h3>Test it</h3>
        <div class="mfa-test">
            curl -s -H 'Accept: text/markdown' https://yourdomain.com/
        </div>
    <?php else: ?>
        <div class="mfa-status mfa-info">
            <strong>Status: Disabled</strong><br>
            Markdown conversion is available but not enabled for your account.
        </div>

        <form method="POST">
            <input type="hidden" name="action" value="enable">
            <button type="submit" class="mfa-btn mfa-btn-enable">Enable Markdown Conversion</button>
        </form>
    <?php endif; ?>

    <h3>How it works</h3>
    <ul>
        <li>When an AI agent (or any client) sends <code>Accept: text/markdown</code>, your site's HTML is automatically converted to clean Markdown.</li>
        <li>Normal browser requests are completely unaffected &mdash; zero overhead.</li>
        <li>Token counts are embedded in the response for AI cost estimation.</li>
    </ul>
<?php endif; ?>

<hr>
<p style="color:#888; font-size:12px;">
    markdown-for-agents v<?= htmlspecialchars($version) ?>
</p>

</div>
