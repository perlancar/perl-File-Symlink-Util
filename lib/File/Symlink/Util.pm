package File::Symlink::Util;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter 'import';
use File::Spec;

# AUTHORITY
# DATE
# DIST
# VERSION

our @EXPORT_OK = qw(
                       symlink_rel
                       symlink_abs
                       adjust_rel_symlink
                       check_symlink
               );

our %SPEC;

sub symlink_rel {
    my ($dest_path, $link_path) = @_;
    symlink(File::Spec->abs2rel($dest_path), $link_path);
}

sub symlink_abs {
    my ($dest_path, $link_path) = @_;
    symlink(File::Spec->rel2abs($dest_path), $link_path);
}

sub adjust_rel_symlink {
    require File::Basename;
    require Path::Naive;

    my ($link_path1, $link_path2) = @_;

    unless (-l $link_path1) {
        log_warn "First path '$link_path1' is not a symlink, skipping adjusting";
        return;
    }
    unless (-l $link_path2) {
        log_warn "Second path '$link_path2' is not a symlink, skipping adjusting";
        return;
    }

    my $dest_path1 = readlink $link_path1;
    if (!defined $dest_path1) {
        log_warn "Cannot read first symlink %s, skipping adjusting", $link_path1;
        return;
    }
    my $dest_path2 = readlink $link_path2;
    if (!defined $dest_path2) {
        log_warn "Cannot read second symlink %s, skipping adjusting", $link_path2;
        return;
    }

    if (File::Spec->file_name_is_absolute($dest_path1)) {
        log_trace "First symlink %s (target '%s') is not relative path, skipping adjusting", $link_path1, $dest_path1;
        return;
    }
    if (File::Spec->file_name_is_absolute($dest_path2)) {
        log_trace "Second symlink %s (target '%s') is not relative path, skipping adjusting", $link_path2, $dest_path2;
        return;
    }
    my $new_dest_path2 = Path::Naive::normalize_path(
        File::Spec->abs2rel(
            (File::Spec->rel2abs($dest_path1, File::Basename::dirname($link_path1))),
            File::Spec->rel2abs(File::Basename::dirname(File::Spec->rel2abs($link_path2)), "/"), # XXX "/" is unixism
        )
    );
    if ($dest_path2 eq $new_dest_path2) {
        log_trace "Skipping adjusting second symlink %s (no change: %s)", $link_path2, $new_dest_path2;
        return;
    }
    unlink $link_path2 or do {
        log_error "Cannot adjust second symlink %s (can't unlink: %s)", $link_path2, $!;
        return;
    };
    symlink($new_dest_path2, $link_path2) or do {
        log_error "Cannot adjust second symlink %s (can't symlink to '%s': %s)", $link_path2, $new_dest_path2, $!;
        return;
    };
    log_trace "Adjusted symlink %s (from target '%s' to target '%s')", $link_path2, $dest_path2, $new_dest_path2;
    1;
}

$SPEC{check_symlink} = {
    v => 1.1,
    summary => "Perform various checks on a symlink",
    args => {
        symlink => {
            summary => "Path to the symlink to be checked",
            schema => "filename*",
            req => 1,
            pos => 0,
        },
        target => {
            summary => "Expected target path",
            schema => "filename*",
            pos => 1,
            description => <<'_',

If specified, then target of symlink (after normalized to absolute path) will be
checked and must point to this target.

_
        },
        is_abs => {
            summary => 'Whether we should check that symlink target is an absolute path',
            schema => 'bool',
            description => <<'_',

If set to true, then symlink target must be an absolute path. If
set to false, then symlink target must be a relative path.

_
        },
        ext_matches => {
            summary => 'Whether extension should match',
            schema => 'bool',
            description => <<'_',

If set to true, then if both symlink name and target filename contain filename
extension (e.g. `jpg`) then they must match. Case variation is allowed (e.g.
`JPG`) but other variation is not (e.g. `jpeg`).

_
        },
        content_matches => {
            summary => 'Whether content should match extension',
            schema => 'bool',
            description => <<'_',

If set to true, will guess media type from content and check that file extension
exists nd matches the media type. Requires <pm:File::MimeInfo::Magic>, which is
only specified as a "Recommends" dependency by File-Symlink-Util distribution.

_
        },
    },
};

sub check_symlink {
    my %args = @_;
    my $res = [200, "OK", []];

    my $symlink; defined($symlink = $args{symlink}) or return [400, "Please specify 'symlink' argument"];
    (-l $symlink) or do { push @{ $res->[2] }, (-e _) ? "File is not a symlink" : "File does not exist"; goto END_CHECK };
    my $target = readlink $symlink;
    (-e $target) or do { push @{ $res->[2] }, "Broken symlink, target does not exist ($target)"; goto END_CHECK };
    if (defined $args{is_abs}) {
        require File::Spec;
        if ($args{is_abs}) {
            unless (File::Spec->file_name_is_absolute($target)) {
                push @{ $res->[2] }, "Symlink target is not an absolute path";
            }
        } else {
            if (File::Spec->file_name_is_absolute($target)) {
                push @{ $res->[2] }, "Symlink target is not a relative path";
            }
        }
    }
    if (defined $args{target}) {
        require Cwd;
        my $wanted_abs_target = Cwd::abs_path($args{target});
        my $abs_target = Cwd::abs_path($target);
        unless ($wanted_abs_target eq $abs_target) {
            push @{ $res->[2] }, "Symlink target is not the same as wanted ($args{target})";
        }
    }
  CHECK_EXT_MATCHES: {
        if ($args{ext_matches}) {
            my ($symlink_ext) = $symlink =~ /\.(\w+)\z/;
            my ($target_ext)  = $target  =~ /\.(\w+)\z/;
            last CHECK_EXT_MATCHES unless defined $symlink_ext && defined $target_ext;
            unless (lc($symlink_ext) eq lc($target_ext)) {
                push @{ $res->[2] }, "Symlink extension ($symlink_ext) does not match target's ($target_ext)";
            }
        }
    }
  CHECK_CONTENT_MATCHES: {
        if ($args{content_matches}) {
            require File::MimeInfo::Magic;
            my ($symlink_ext) = $symlink =~ /\.(\w+)\z/;
            open my $fh, "<", $symlink or do { push @{ $res->[2] }, "Can't open symlink target for content checking: $!"; last CHECK_CONTENT_MATCHES };
            my $type = File::MimeInfo::Magic::mimetype($fh);
            my @exts; @exts = File::MimeInfo::Magic::extensions($type) if $type;
            if (defined($symlink_ext) && @exts) {
                my $found;
                for my $ext (@exts) {
                    if (lc $ext eq lc $symlink_ext) { $found++; last }
                }
                unless ($found) {
                    push @{ $res->[2] }, "Symlink extension ($symlink_ext) does not match content type ($type, exts=".join("|", @exts).")";
                }
            } elsif (defined($symlink_ext) xor @exts) {
                if (defined $symlink_ext) {
                    push @{ $res->[2] }, "Content type is unknown but symlink has extension ($symlink_ext)";
                } else {
                    push @{ $res->[2] }, "Content type is $type but symlink does not have any extension";
                }
            } else {
                # mime type is unknown and file does not have extension -> OK
            }
        }
    }

  END_CHECK:
    if (@{ $res->[2] }) { $res->[0] = 500; $res->[1] = "Errors" }
    $res;
}

1;
# ABSTRACT: Utilities related to symbolic links

=head1 SYNOPSIS

 use File::Symlink::Util qw(
                       symlink_rel
                       symlink_abs
                       adjust_rel_symlink
                       check_symlink
 );

 chdir "/home/ujang";

 # create a relative path symlink
 symlink_rel "/etc/passwd", "symlink1";      # symlink1 -> ../../etc/passwd
 symlink_rel "../../etc/passwd", "symlink1"; # symlink1 -> ../../etc/passwd

 # create an absolute path symlink
 symlink_abs "/etc/passwd", "symlink1";      # symlink1 -> ../../etc/passwd
 symlink_abs "../../etc/passwd", "symlink1"; # symlink1 -> ../../etc/passwd

 # adjust second symlink to be relative to the second path
 symlink "dir1/target", "symlink1";
 % cp -a  "symlink1", "dir2/symlink2";           # dir2/symlink2 points to dir1/target, which is now broken
 adjust_rel_symlink "symlink1", "dir2/symlink2"; # dir2/symlink2 is now fixed, points to ../dir1/target

 # check various aspects of a symlink
 my $res = check_symlink(symlink => "symlink1");                                     # => [200, "OK", []]
 my $res = check_symlink(symlink => "not-a-symlink");                                # => [500, "Errors", ["File is not a symlink"]]
 my $res = check_symlink(symlink => "link-to-a-pic.txt", is_abs=>1, ext_matches=>1); # => [500, "Errors", ["Symlink target is not absolute path", "Extension of symlink does not match target's (jpg)"]]


=head1 DESCRIPTION


=head1 prepend:FUNCTIONS

=head2 symlink_rel

Usage:

 symlink_rel($dest_path, $link_path);

Create a relative path symlink. Basically perform C<<
File::Spec->abs2rel($dest_path) >> before C<< symlink() >>.

=head2 symlink_abs

Usage:

 symlink_rel($dest_path, $link_path);

Create an absolute path symlink. Basically perform C<<
File::Spec->rel2abs($dest_path) >> before C<< symlink() >>.

=head2 adjust_rel_symlink

Usage:

 adjust_rel_symlink($link_path1, $link_path2);

Adjust relative symlink in C<$link_path2> (that used to be relative to
C<$link_path1>) so that its target now becomes relative to C<$link_path2>.

This is useful if you copy a relative symlink e.g. C<$link_path1> to
C<$link_path2>. Because the target is not adjusted, and you want the new symlink
to point to the original target. See example in Synopsis for illustration.

Both C<$link_path1> and C<$link_path2> must be symlink.


=head1 SEE ALSO

=head2 Other symlink-related routines

L<File::Symlink::Relative> provides C<symlink_r> to create relative symlinks,
which is the same as L</symlink_rel>.

L<File::MoreUtil> provides C<file_exists> and C<l_abs_path>.

=cut
