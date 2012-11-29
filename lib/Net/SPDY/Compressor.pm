package Net::SPDY::Compressor;

=head1 NAME

Net::SPDY::Compressor - SPDY header compressor

=head1 ALPHA WARNING

B<Please read carefully:> This is an ALPHA stage software.
In particular this means that even though it probably won't kill your cat,
re-elect George W. Bush nor install Solaris 11 Express edition to your hard
drive, it is in active development, functionality is missing and no APIs are
stable.

See F<TODO> file in the distribution to learn about missing and planned
functionality. You are more than welcome to join the development and submit
patches with fixes or enhancements.  Bug reports are probably not very useful
at this point.

=head1 SYNOPSIS

  use Net::SPDY::Compressor;

  my $compr = new Net::SPDY::Compressor;
  print $compr->uncompress($compr->compress("Hello, World!\n"));

=head1 DESCRIPTION

B<Net::SPDY::Compressor> provides a convenient way to compress data
in a way used by the SPDY protocol.

This, in particular, means, that there are two separate streams (for input and
output), streams are synced after each message and the stream is initialized
with a dictionary of strings common to web communication.

=cut

use strict;
use warnings;

use Compress::Zlib qw/inflateInit deflateInit Z_SYNC_FLUSH/;

our $VERSION = '0.1';

=head1 CONSTANTS

For the actual values refer to the protocol specification.

=over 4

=item C<DICT>

The initial SPDY compression dictionary.

=back

=cut

use constant DICT =>
	"\x00\x00\x00\x07\x6f\x70\x74\x69". #----opti
	"\x6f\x6e\x73\x00\x00\x00\x04\x68". #ons----h
	"\x65\x61\x64\x00\x00\x00\x04\x70". #ead----p
	"\x6f\x73\x74\x00\x00\x00\x03\x70". #ost----p
	"\x75\x74\x00\x00\x00\x06\x64\x65". #ut----de
	"\x6c\x65\x74\x65\x00\x00\x00\x05". #lete----
	"\x74\x72\x61\x63\x65\x00\x00\x00". #trace---
	"\x06\x61\x63\x63\x65\x70\x74\x00". #-accept-
	"\x00\x00\x0e\x61\x63\x63\x65\x70". #---accep
	"\x74\x2d\x63\x68\x61\x72\x73\x65". #t-charse
	"\x74\x00\x00\x00\x0f\x61\x63\x63". #t----acc
	"\x65\x70\x74\x2d\x65\x6e\x63\x6f". #ept-enco
	"\x64\x69\x6e\x67\x00\x00\x00\x0f". #ding----
	"\x61\x63\x63\x65\x70\x74\x2d\x6c". #accept-l
	"\x61\x6e\x67\x75\x61\x67\x65\x00". #anguage-
	"\x00\x00\x0d\x61\x63\x63\x65\x70". #---accep
	"\x74\x2d\x72\x61\x6e\x67\x65\x73". #t-ranges
	"\x00\x00\x00\x03\x61\x67\x65\x00". #----age-
	"\x00\x00\x05\x61\x6c\x6c\x6f\x77". #---allow
	"\x00\x00\x00\x0d\x61\x75\x74\x68". #----auth
	"\x6f\x72\x69\x7a\x61\x74\x69\x6f". #orizatio
	"\x6e\x00\x00\x00\x0d\x63\x61\x63". #n----cac
	"\x68\x65\x2d\x63\x6f\x6e\x74\x72". #he-contr
	"\x6f\x6c\x00\x00\x00\x0a\x63\x6f". #ol----co
	"\x6e\x6e\x65\x63\x74\x69\x6f\x6e". #nnection
	"\x00\x00\x00\x0c\x63\x6f\x6e\x74". #----cont
	"\x65\x6e\x74\x2d\x62\x61\x73\x65". #ent-base
	"\x00\x00\x00\x10\x63\x6f\x6e\x74". #----cont
	"\x65\x6e\x74\x2d\x65\x6e\x63\x6f". #ent-enco
	"\x64\x69\x6e\x67\x00\x00\x00\x10". #ding----
	"\x63\x6f\x6e\x74\x65\x6e\x74\x2d". #content-
	"\x6c\x61\x6e\x67\x75\x61\x67\x65". #language
	"\x00\x00\x00\x0e\x63\x6f\x6e\x74". #----cont
	"\x65\x6e\x74\x2d\x6c\x65\x6e\x67". #ent-leng
	"\x74\x68\x00\x00\x00\x10\x63\x6f". #th----co
	"\x6e\x74\x65\x6e\x74\x2d\x6c\x6f". #ntent-lo
	"\x63\x61\x74\x69\x6f\x6e\x00\x00". #cation--
	"\x00\x0b\x63\x6f\x6e\x74\x65\x6e". #--conten
	"\x74\x2d\x6d\x64\x35\x00\x00\x00". #t-md5---
	"\x0d\x63\x6f\x6e\x74\x65\x6e\x74". #-content
	"\x2d\x72\x61\x6e\x67\x65\x00\x00". #-range--
	"\x00\x0c\x63\x6f\x6e\x74\x65\x6e". #--conten
	"\x74\x2d\x74\x79\x70\x65\x00\x00". #t-type--
	"\x00\x04\x64\x61\x74\x65\x00\x00". #--date--
	"\x00\x04\x65\x74\x61\x67\x00\x00". #--etag--
	"\x00\x06\x65\x78\x70\x65\x63\x74". #--expect
	"\x00\x00\x00\x07\x65\x78\x70\x69". #----expi
	"\x72\x65\x73\x00\x00\x00\x04\x66". #res----f
	"\x72\x6f\x6d\x00\x00\x00\x04\x68". #rom----h
	"\x6f\x73\x74\x00\x00\x00\x08\x69". #ost----i
	"\x66\x2d\x6d\x61\x74\x63\x68\x00". #f-match-
	"\x00\x00\x11\x69\x66\x2d\x6d\x6f". #---if-mo
	"\x64\x69\x66\x69\x65\x64\x2d\x73". #dified-s
	"\x69\x6e\x63\x65\x00\x00\x00\x0d". #ince----
	"\x69\x66\x2d\x6e\x6f\x6e\x65\x2d". #if-none-
	"\x6d\x61\x74\x63\x68\x00\x00\x00". #match---
	"\x08\x69\x66\x2d\x72\x61\x6e\x67". #-if-rang
	"\x65\x00\x00\x00\x13\x69\x66\x2d". #e----if-
	"\x75\x6e\x6d\x6f\x64\x69\x66\x69". #unmodifi
	"\x65\x64\x2d\x73\x69\x6e\x63\x65". #ed-since
	"\x00\x00\x00\x0d\x6c\x61\x73\x74". #----last
	"\x2d\x6d\x6f\x64\x69\x66\x69\x65". #-modifie
	"\x64\x00\x00\x00\x08\x6c\x6f\x63". #d----loc
	"\x61\x74\x69\x6f\x6e\x00\x00\x00". #ation---
	"\x0c\x6d\x61\x78\x2d\x66\x6f\x72". #-max-for
	"\x77\x61\x72\x64\x73\x00\x00\x00". #wards---
	"\x06\x70\x72\x61\x67\x6d\x61\x00". #-pragma-
	"\x00\x00\x12\x70\x72\x6f\x78\x79". #---proxy
	"\x2d\x61\x75\x74\x68\x65\x6e\x74". #-authent
	"\x69\x63\x61\x74\x65\x00\x00\x00". #icate---
	"\x13\x70\x72\x6f\x78\x79\x2d\x61". #-proxy-a
	"\x75\x74\x68\x6f\x72\x69\x7a\x61". #uthoriza
	"\x74\x69\x6f\x6e\x00\x00\x00\x05". #tion----
	"\x72\x61\x6e\x67\x65\x00\x00\x00". #range---
	"\x07\x72\x65\x66\x65\x72\x65\x72". #-referer
	"\x00\x00\x00\x0b\x72\x65\x74\x72". #----retr
	"\x79\x2d\x61\x66\x74\x65\x72\x00". #y-after-
	"\x00\x00\x06\x73\x65\x72\x76\x65". #---serve
	"\x72\x00\x00\x00\x02\x74\x65\x00". #r----te-
	"\x00\x00\x07\x74\x72\x61\x69\x6c". #---trail
	"\x65\x72\x00\x00\x00\x11\x74\x72". #er----tr
	"\x61\x6e\x73\x66\x65\x72\x2d\x65". #ansfer-e
	"\x6e\x63\x6f\x64\x69\x6e\x67\x00". #ncoding-
	"\x00\x00\x07\x75\x70\x67\x72\x61". #---upgra
	"\x64\x65\x00\x00\x00\x0a\x75\x73". #de----us
	"\x65\x72\x2d\x61\x67\x65\x6e\x74". #er-agent
	"\x00\x00\x00\x04\x76\x61\x72\x79". #----vary
	"\x00\x00\x00\x03\x76\x69\x61\x00". #----via-
	"\x00\x00\x07\x77\x61\x72\x6e\x69". #---warni
	"\x6e\x67\x00\x00\x00\x10\x77\x77". #ng----ww
	"\x77\x2d\x61\x75\x74\x68\x65\x6e". #w-authen
	"\x74\x69\x63\x61\x74\x65\x00\x00". #ticate--
	"\x00\x06\x6d\x65\x74\x68\x6f\x64". #--method
	"\x00\x00\x00\x03\x67\x65\x74\x00". #----get-
	"\x00\x00\x06\x73\x74\x61\x74\x75". #---statu
	"\x73\x00\x00\x00\x06\x32\x30\x30". #s----200
	"\x20\x4f\x4b\x00\x00\x00\x07\x76". #-OK----v
	"\x65\x72\x73\x69\x6f\x6e\x00\x00". #ersion--
	"\x00\x08\x48\x54\x54\x50\x2f\x31". #--HTTP-1
	"\x2e\x31\x00\x00\x00\x03\x75\x72". #-1----ur
	"\x6c\x00\x00\x00\x06\x70\x75\x62". #l----pub
	"\x6c\x69\x63\x00\x00\x00\x0a\x73". #lic----s
	"\x65\x74\x2d\x63\x6f\x6f\x6b\x69". #et-cooki
	"\x65\x00\x00\x00\x0a\x6b\x65\x65". #e----kee
	"\x70\x2d\x61\x6c\x69\x76\x65\x00". #p-alive-
	"\x00\x00\x06\x6f\x72\x69\x67\x69". #---origi
	"\x6e\x31\x30\x30\x31\x30\x31\x32". #n1001012
	"\x30\x31\x32\x30\x32\x32\x30\x35". #01202205
	"\x32\x30\x36\x33\x30\x30\x33\x30". #20630030
	"\x32\x33\x30\x33\x33\x30\x34\x33". #23033043
	"\x30\x35\x33\x30\x36\x33\x30\x37". #05306307
	"\x34\x30\x32\x34\x30\x35\x34\x30". #40240540
	"\x36\x34\x30\x37\x34\x30\x38\x34". #64074084
	"\x30\x39\x34\x31\x30\x34\x31\x31". #09410411
	"\x34\x31\x32\x34\x31\x33\x34\x31". #41241341
	"\x34\x34\x31\x35\x34\x31\x36\x34". #44154164
	"\x31\x37\x35\x30\x32\x35\x30\x34". #17502504
	"\x35\x30\x35\x32\x30\x33\x20\x4e". #505203-N
	"\x6f\x6e\x2d\x41\x75\x74\x68\x6f". #on-Autho
	"\x72\x69\x74\x61\x74\x69\x76\x65". #ritative
	"\x20\x49\x6e\x66\x6f\x72\x6d\x61". #-Informa
	"\x74\x69\x6f\x6e\x32\x30\x34\x20". #tion204-
	"\x4e\x6f\x20\x43\x6f\x6e\x74\x65". #No-Conte
	"\x6e\x74\x33\x30\x31\x20\x4d\x6f". #nt301-Mo
	"\x76\x65\x64\x20\x50\x65\x72\x6d". #ved-Perm
	"\x61\x6e\x65\x6e\x74\x6c\x79\x34". #anently4
	"\x30\x30\x20\x42\x61\x64\x20\x52". #00-Bad-R
	"\x65\x71\x75\x65\x73\x74\x34\x30". #equest40
	"\x31\x20\x55\x6e\x61\x75\x74\x68". #1-Unauth
	"\x6f\x72\x69\x7a\x65\x64\x34\x30". #orized40
	"\x33\x20\x46\x6f\x72\x62\x69\x64". #3-Forbid
	"\x64\x65\x6e\x34\x30\x34\x20\x4e". #den404-N
	"\x6f\x74\x20\x46\x6f\x75\x6e\x64". #ot-Found
	"\x35\x30\x30\x20\x49\x6e\x74\x65". #500-Inte
	"\x72\x6e\x61\x6c\x20\x53\x65\x72". #rnal-Ser
	"\x76\x65\x72\x20\x45\x72\x72\x6f". #ver-Erro
	"\x72\x35\x30\x31\x20\x4e\x6f\x74". #r501-Not
	"\x20\x49\x6d\x70\x6c\x65\x6d\x65". #-Impleme
	"\x6e\x74\x65\x64\x35\x30\x33\x20". #nted503-
	"\x53\x65\x72\x76\x69\x63\x65\x20". #Service-
	"\x55\x6e\x61\x76\x61\x69\x6c\x61". #Unavaila
	"\x62\x6c\x65\x4a\x61\x6e\x20\x46". #bleJan-F
	"\x65\x62\x20\x4d\x61\x72\x20\x41". #eb-Mar-A
	"\x70\x72\x20\x4d\x61\x79\x20\x4a". #pr-May-J
	"\x75\x6e\x20\x4a\x75\x6c\x20\x41". #un-Jul-A
	"\x75\x67\x20\x53\x65\x70\x74\x20". #ug-Sept-
	"\x4f\x63\x74\x20\x4e\x6f\x76\x20". #Oct-Nov-
	"\x44\x65\x63\x20\x30\x30\x3a\x30". #Dec-00-0
	"\x30\x3a\x30\x30\x20\x4d\x6f\x6e". #0-00-Mon
	"\x2c\x20\x54\x75\x65\x2c\x20\x57". #--Tue--W
	"\x65\x64\x2c\x20\x54\x68\x75\x2c". #ed--Thu-
	"\x20\x46\x72\x69\x2c\x20\x53\x61". #-Fri--Sa
	"\x74\x2c\x20\x53\x75\x6e\x2c\x20". #t--Sun--
	"\x47\x4d\x54\x63\x68\x75\x6e\x6b". #GMTchunk
	"\x65\x64\x2c\x74\x65\x78\x74\x2f". #ed-text-
	"\x68\x74\x6d\x6c\x2c\x69\x6d\x61". #html-ima
	"\x67\x65\x2f\x70\x6e\x67\x2c\x69". #ge-png-i
	"\x6d\x61\x67\x65\x2f\x6a\x70\x67". #mage-jpg
	"\x2c\x69\x6d\x61\x67\x65\x2f\x67". #-image-g
	"\x69\x66\x2c\x61\x70\x70\x6c\x69". #if-appli
	"\x63\x61\x74\x69\x6f\x6e\x2f\x78". #cation-x
	"\x6d\x6c\x2c\x61\x70\x70\x6c\x69". #ml-appli
	"\x63\x61\x74\x69\x6f\x6e\x2f\x78". #cation-x
	"\x68\x74\x6d\x6c\x2b\x78\x6d\x6c". #html-xml
	"\x2c\x74\x65\x78\x74\x2f\x70\x6c". #-text-pl
	"\x61\x69\x6e\x2c\x74\x65\x78\x74". #ain-text
	"\x2f\x6a\x61\x76\x61\x73\x63\x72". #-javascr
	"\x69\x70\x74\x2c\x70\x75\x62\x6c". #ipt-publ
	"\x69\x63\x70\x72\x69\x76\x61\x74". #icprivat
	"\x65\x6d\x61\x78\x2d\x61\x67\x65". #emax-age
	"\x3d\x67\x7a\x69\x70\x2c\x64\x65". #-gzip-de
	"\x66\x6c\x61\x74\x65\x2c\x73\x64". #flate-sd
	"\x63\x68\x63\x68\x61\x72\x73\x65". #chcharse
	"\x74\x3d\x75\x74\x66\x2d\x38\x63". #t-utf-8c
	"\x68\x61\x72\x73\x65\x74\x3d\x69". #harset-i
	"\x73\x6f\x2d\x38\x38\x35\x39\x2d". #so-8859-
	"\x31\x2c\x75\x74\x66\x2d\x2c\x2a". #1-utf---
	"\x2c\x65\x6e\x71\x3d\x30\x2e";     #-enq-0-

=head1 METHODS

=over 4

=item new

Creates a new compressor instance.

=cut

sub new
{
	my $class = shift;
	my $self = bless {}, $class;

	# Initiate the Zlib streams
	my $status;
	($self->{inflater}, $status) = inflateInit (
		-Dictionary => DICT);
	die $status if $status;
	($self->{deflater}, $status) = deflateInit (
		-Level => 0,
		-Dictionary => DICT);
	die $status if $status;

	return $self;
}

=item compress STRING

Returns a compressed string.

=cut

sub compress
{
	my $self = shift;
	my $msg = shift;

	my ($o1, $o2, $status);
	($o1, $status) = $self->{deflater}->deflate ($msg);
	die $status if $status;
	($o2, $status) = $self->{deflater}->flush (Z_SYNC_FLUSH);
	die $status if $status;

	return $o1.$o2;
}

=item uncompress STRING

Returns an uncompressed string given a compressed one.

=cut

sub uncompress
{
	my $self = shift;
	my $msg = shift;

	my ($out, $status) = $self->{inflater}->inflate (\$msg);
	die $status if $status;

	return $out;
}

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<http://www.chromium.org/spdy/spdy-protocol/spdy-protocol-draft3> -- Protocol specification

=back

=head1 CONTRIBUTING

Source code for I<Net::SPDY> is kept in a public GIT repository.
Visit L<https://github.com/lkundrak/net-spdy>.

Bugs reports and feature enhancement requests are tracked at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Net::SPDY>.

=head1 COPYRIGHT

Copyright 2012, Lubomir Rintel

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Lubomir Rintel C<lkundrak@v3.sk>

=cut

1;
