#!/usr/local/cpanel/3rdparty/bin/perl
# addon_markdown_for_agents.cgi — WHM admin page for markdown-for-agents.
#
# Shows global install status, lists accounts, provides enable/disable controls.
# Uses WHM's HTMLInterface to render inside the WHM chrome (sidebar stays live).

use strict;
use warnings;
use CGI ();

BEGIN {
    unshift @INC, '/usr/local/cpanel';
}

use Whostmgr::HTMLInterface ();
use Whostmgr::ACLS          ();

# --- WHM access control ---

Whostmgr::ACLS::init_acls();
unless (Whostmgr::ACLS::hasroot()) {
    print "Content-Type: text/html\r\n\r\n";
    print "Access denied.";
    exit;
}

print "Content-Type: text/html\r\n\r\n";
Whostmgr::HTMLInterface::defheader('Markdown for Agents');

my $MFA_DIR     = '/opt/markdown-for-agents';
my $SCRIPTS_DIR = "$MFA_DIR/cpanel/scripts";

my $cgi = CGI->new();

my $action   = $cgi->param('action')   // '';
my $username = $cgi->param('username')  // '';

# --- Process actions ---

my $action_msg = '';
my $action_err = '';

if ($action eq 'enable' && $username) {
    my $safe_user = quotemeta($username);
    my $out = qx{sudo $SCRIPTS_DIR/mfa-account-enable.sh $safe_user 2>&1};
    if ($? == 0) {
        $action_msg = "Enabled markdown-for-agents for <b>$username</b>";
    } else {
        $action_err = "Failed to enable for $username: <pre>$out</pre>";
    }
}
elsif ($action eq 'disable' && $username) {
    my $safe_user = quotemeta($username);
    my $out = qx{sudo $SCRIPTS_DIR/mfa-account-disable.sh $safe_user 2>&1};
    if ($? == 0) {
        $action_msg = "Disabled markdown-for-agents for <b>$username</b>";
    } else {
        $action_err = "Failed to disable for $username: <pre>$out</pre>";
    }
}
elsif ($action eq 'global_install') {
    my $out = qx{sudo $SCRIPTS_DIR/mfa-global-install.sh 2>&1};
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
    if (open my $fh, '<', "$MFA_DIR/.installed") {
        $global_version = <$fh> // '';
        close $fh;
        chomp $global_version;
    }
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

# --- Render page content (inside WHM chrome) ---

my $self = $cgi->url(-relative => 1);

print <<STYLE;
<style>
    .mfa-box { padding: 15px; margin: 15px 0; border-radius: 6px; }
    .mfa-ok { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
    .mfa-warn { background: #fff3cd; border: 1px solid #ffeeba; color: #856404; }
    .mfa-err { background: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
    .mfa-table { border-collapse: collapse; width: 100%; margin: 20px 0; }
    .mfa-table th, .mfa-table td { border: 1px solid #dee2e6; padding: 10px 14px; text-align: left; }
    .mfa-table th { background: #f8f9fa; }
    .mfa-btn { display: inline-block; padding: 6px 16px; border-radius: 4px; text-decoration: none;
               font-size: 14px; cursor: pointer; border: none; color: white; }
    .mfa-btn-enable { background: #28a745; }
    .mfa-btn-enable:hover { background: #218838; }
    .mfa-btn-disable { background: #dc3545; }
    .mfa-btn-disable:hover { background: #c82333; }
    .mfa-btn-install { background: #007bff; }
    .mfa-btn-install:hover { background: #0069d9; }
    .mfa-badge { display: inline-block; padding: 3px 8px; border-radius: 3px; font-size: 12px; font-weight: bold; }
    .mfa-badge-on { background: #28a745; color: white; }
    .mfa-badge-off { background: #6c757d; color: white; }
</style>

<p>HTML-to-Markdown conversion via <code>Accept: text/markdown</code> content negotiation.</p>
STYLE

# Action messages
if ($action_msg) {
    print qq{<div class="mfa-box mfa-ok">$action_msg</div>\n};
}
if ($action_err) {
    print qq{<div class="mfa-box mfa-err">$action_err</div>\n};
}

# Global status
if ($global_installed) {
    print qq{<div class="mfa-box mfa-ok">};
    print qq{<strong>Global infrastructure:</strong> Installed (v$global_version)};
    print qq{</div>\n};
} else {
    print qq{<div class="mfa-box mfa-warn">};
    print qq{<strong>Global infrastructure:</strong> Not installed};
    print qq{ &mdash; <a href="$self?action=global_install" class="mfa-btn mfa-btn-install">Install Now</a>};
    print qq{</div>\n};
}

if ($global_installed) {
    my $enabled_count = grep { $account_status{$_} } @accounts;
    my $total = scalar @accounts;

    print <<TABLE_HEAD;
<h2>Customer Accounts</h2>
<p>$enabled_count of $total account(s) enabled.</p>
<table class="mfa-table">
    <tr>
        <th>Account</th>
        <th>Status</th>
        <th>Action</th>
    </tr>
TABLE_HEAD

    for my $acct (@accounts) {
        my $enabled = $account_status{$acct};
        my $badge = $enabled
            ? '<span class="mfa-badge mfa-badge-on">Enabled</span>'
            : '<span class="mfa-badge mfa-badge-off">Disabled</span>';
        my $btn = $enabled
            ? qq{<a href="$self?action=disable&username=$acct" class="mfa-btn mfa-btn-disable">Disable</a>}
            : qq{<a href="$self?action=enable&username=$acct" class="mfa-btn mfa-btn-enable">Enable</a>};

        print qq{    <tr><td>$acct</td><td>$badge</td><td>$btn</td></tr>\n};
    }

    print "</table>\n";
}

print <<FOOTER;
<hr>
<p style="color:#888; font-size:12px;">
    markdown-for-agents &mdash; Apache output filter for AI agents.
</p>
FOOTER

Whostmgr::HTMLInterface::footer();
