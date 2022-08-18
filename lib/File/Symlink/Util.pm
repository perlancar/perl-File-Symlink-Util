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
               );


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

1;
# ABSTRACT: Utilities related to symbolic links

=head1 SYNOPSIS

 use File::Symlink::Util qw(
                       symlink_rel
                       symlink_abs
                       adjust_rel_symlink
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


=head1 DESCRIPTION


=head1 FUNCTIONS

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
C<$link_path2>. Because the target is not adjusted, and want the new symlink to
point to the original target.

Both C<$link_path1> and C<$link_path2> must be symlink.

=head1 SEE ALSO

=head2 Other symlink-related routines

L<File::Symlink::Relative> provides C<symlink_r> to create relative symlinks,
which is the same as L</symlink_rel>.

L<File::MoreUtil> provides C<file_exists> and C<l_abs_path>.

=cut
