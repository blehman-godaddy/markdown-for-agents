#!/usr/local/cpanel/3rdparty/bin/perl
# addon_markdown_for_agents.cgi — WHM admin page for markdown-for-agents.
#
# Shows global install status, lists accounts, provides enable/disable controls.

use strict;
use warnings;
use CGI ();
use JSON::XS ();

my $MFA_DIR       = '/opt/markdown-for-agents';
my $SCRIPTS_DIR   = "$MFA_DIR/../cpanel/scripts";
# Fall back to well-known plugin location
unless (-d $SCRIPTS_DIR) {
    $SCRIPTS_DIR = '/usr/local/cpanel/whostmgr/cgi/addons/markdown_for_agents/scripts';
}
# Fall back again to installed location
unless (-d $SCRIPTS_DIR) {
    $SCRIPTS_DIR = "$MFA_DIR/cpanel/scripts";
}

my $cgi = CGI->new();

# --- WHM security: require root/reseller ---
print "Content-Type: text/html\r\n\r\n";

my $action   = $cgi->param('action')   // '';
my $username = $cgi->param('username')  // '';

# --- Process actions ---

my $action_msg = '';
my $action_err = '';

if ($action eq 'enable' && $username) {
    my $out = qx{sudo /opt/markdown-for-agents/cpanel/scripts/mfa-account-enable.sh \Q$username\E 2>&1};
    if ($? == 0) {
        $action_msg = "Enabled markdown-for-agents for <b>$username</b>";
    } else {
        $action_err = "Failed to enable for $username: <pre>$out</pre>";
    }
}
elsif ($action eq 'disable' && $username) {
    my $out = qx{sudo /opt/markdown-for-agents/cpanel/scripts/mfa-account-disable.sh \Q$username\E 2>&1};
    if ($? == 0) {
        $action_msg = "Disabled markdown-for-agents for <b>$username</b>";
    } else {
        $action_err = "Failed to disable for $username: <pre>$out</pre>";
    }
}
elsif ($action eq 'global_install') {
    my $out = qx{sudo /opt/markdown-for-agents/cpanel/scripts/mfa-global-install.sh 2>&1};
    if ($? == 0) {
        $action_msg = "Global infrastructure installed successfully";
    } else {
        $action_err = "Global install failed: <pre>$out</pre>";
    }
}

# --- Check global status ---

my $global_installed = (-f "$MFA_DIR/.installed") ? 1 : 0;
my $global_version   = '';
if ($global_installed) {
    open my $fh, '<', "$MFA_DIR/.installed";
    $global_version = <$fh> // '';
    close $fh;
    chomp $global_version;
}

# --- Get list of cPanel accounts ---

my @accounts;
my $userdata_dir = '/var/cpanel/users';
if (opendir my $dh, $userdata_dir) {
    @accounts = sort grep { !/^\./ && !/^root$/ && -f "$userdata_dir/$_" } readdir $dh;
    closedir $dh;
}

# Check which accounts have markdown enabled
my %account_status;
for my $acct (@accounts) {
    my $std = "/etc/apache2/conf.d/userdata/std/2_4/$acct/markdown-for-agents.conf";
    my $ssl = "/etc/apache2/conf.d/userdata/ssl/2_4/$acct/markdown-for-agents.conf";
    $account_status{$acct} = (-f $std && -f $ssl) ? 1 : 0;
}

# --- Render page ---

my $self = $cgi->url(-relative => 1);

print <<HTML;
<!DOCTYPE html>
<html>
<head>
    <title>Markdown for Agents</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .status-box { padding: 15px; margin: 15px 0; border-radius: 6px; }
        .status-ok { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
        .status-warn { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; }
        .status-err { background: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #dee2e6; padding: 10px 14px; text-align: left; }
        th { background: #f8f9fa; }
        .btn { display: inline-block; padding: 6px 16px; border-radius: 4px; text-decoration: none;
               font-size: 14px; cursor: pointer; border: none; color: white; }
        .btn-enable { background: #28a745; }
        .btn-enable:hover { background: #218838; }
        .btn-disable { background: #dc3545; }
        .btn-disable:hover { background: #c82333; }
        .btn-install { background: #007bff; }
        .btn-install:hover { background: #0069d9; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 3px; font-size: 12px; font-weight: bold; }
        .badge-on { background: #28a745; color: white; }
        .badge-off { background: #6c757d; color: white; }
    </style>
</head>
<body>

<h1>Markdown for Agents</h1>
<p>HTML-to-Markdown conversion via <code>Accept: text/markdown</code> content negotiation.</p>

HTML

# Action messages
if ($action_msg) {
    print qq{<div class="status-box status-ok">$action_msg</div>\n};
}
if ($action_err) {
    print qq{<div class="status-box status-err">$action_err</div>\n};
}

# Global status
if ($global_installed) {
    print qq{<div class="status-box status-ok">};
    print qq{<strong>Global infrastructure:</strong> Installed (v$global_version)};
    print qq{</div>\n};
} else {
    print qq{<div class="status-box status-warn">};
    print qq{<strong>Global infrastructure:</strong> Not installed};
    print qq{ &mdash; <a href="$self?action=global_install" class="btn btn-install">Install Now</a>};
    print qq{</div>\n};
}

if ($global_installed) {
    # Account table
    my $enabled_count = grep { $account_status{$_} } @accounts;
    my $total = scalar @accounts;

    print <<HTML;
<h2>Customer Accounts</h2>
<p>$enabled_count of $total account(s) enabled.</p>
<table>
    <tr>
        <th>Account</th>
        <th>Status</th>
        <th>Action</th>
    </tr>
HTML

    for my $acct (@accounts) {
        my $enabled = $account_status{$acct};
        my $badge = $enabled
            ? '<span class="badge badge-on">Enabled</span>'
            : '<span class="badge badge-off">Disabled</span>';
        my $btn = $enabled
            ? qq{<a href="$self?action=disable&username=$acct" class="btn btn-disable">Disable</a>}
            : qq{<a href="$self?action=enable&username=$acct" class="btn btn-enable">Enable</a>};

        print qq{    <tr><td>$acct</td><td>$badge</td><td>$btn</td></tr>\n};
    }

    print "</table>\n";
}

print <<HTML;

<hr>
<p style="color:#888; font-size:12px;">
    markdown-for-agents &mdash; Apache output filter for AI agents.
</p>

</body>
</html>
HTML
