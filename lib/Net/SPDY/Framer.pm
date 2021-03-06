package Net::SPDY::Framer;

=head1 NAME

Net::SPDY::Framer - SPDY protocol implementation

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

  use Net::SPDY::Framer;

  my $framer = new Net::SPDY::Framer ({
      compressor => new Net::SPDY::Compressor,
      socket => $socket,
  });

  $framer->write_frame(
        type => Net::SPDY::Framer::PING,
        data => 0x706c6c6d,
  );
  while (my %frame = $framer->read_frame) {
        last if $frame{control} and $frame{type} eq Net::SPDY::Framer::PING;
  }

=head1 DESCRIPTION

B<Net::SPDY::Framer> provides SPDY protocol access on top of a network socket.
It serializes and deserializes packets as they are, without implementing any
other logic. For session management, see L<Net::SPDY::Session>.

=cut

use strict;
use warnings;

our $VERSION = '0.1';

use Errno qw/EINTR/;

=head1 CONSTANTS

For the actual values refer to the protocol specification.

=over 4

=item Frame types

C<SYN_STREAM>, C<SYN_REPLY>, C<RST_STREAM>, C<SETTINGS>, C<PING>, C<GOAWAY>,
C<HEADERS>, C<WINDOW_UPDATE>, C<CREDENTIAL>.

=cut

# Frame types
use constant {
	SYN_STREAM	=> 1,
	SYN_REPLY	=> 2,
	RST_STREAM	=> 3,
	SETTINGS	=> 4,
	PING		=> 6,
	GOAWAY		=> 7,
	HEADERS		=> 8,
	WINDOW_UPDATE	=> 9,
	CREDENTIAL	=> 10,
};

=item Frame flags

C<FLAG_FIN>, C<FLAG_UNIDIRECTIONAL>, C<FLAG_SETTINGS_CLEAR_SETTINGS>.

=cut

use constant {
	# For SYN_STREAM, SYN_RESPONSE, Data
	FLAG_FIN	=> 0x01,
	FLAG_UNIDIRECTIONAL => 0x02,
	# For SETTINGS
	FLAG_SETTINGS_CLEAR_SETTINGS => 0x01,
};

=item SETTINGS flags

C<FLAG_SETTINGS_PERSIST_VALUE>, C<FLAG_SETTINGS_PERSISTED>.

=cut

use constant {
	FLAG_SETTINGS_PERSIST_VALUE => 0x1,
	FLAG_SETTINGS_PERSISTED	=> 0x2,
};

=item SETTINGS values

C<SETTINGS_UPLOAD_BANDWIDTH>, C<SETTINGS_DOWNLOAD_BANDWIDTH>,
C<SETTINGS_ROUND_TRIP_TIME>, C<SETTINGS_MAX_CONCURRENT_STREAMS>,
C<SETTINGS_CURRENT_CWND>, C<SETTINGS_DOWNLOAD_RETRANS_RATE>,
C<SETTINGS_INITIAL_WINDOW_SIZE>, C<SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE>.

=cut

use constant {
	SETTINGS_UPLOAD_BANDWIDTH => 1,
	SETTINGS_DOWNLOAD_BANDWIDTH => 2,
	SETTINGS_ROUND_TRIP_TIME => 3,
	SETTINGS_MAX_CONCURRENT_STREAMS => 4,
	SETTINGS_CURRENT_CWND => 5,
	SETTINGS_DOWNLOAD_RETRANS_RATE => 6,
	SETTINGS_INITIAL_WINDOW_SIZE => 7,
	SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE	=> 8,
};

=back

=head1 PROPERTIES

=over 4

=item compressor

L<Net::SPDY::Compressor> object representing the Zlib streams (one in each
direction) used by the framer.

=item socket

L<IO::Handle> instance that is used for actual network communication.

=cut

sub pack_nv
{
	my $self = shift;

	my $name_value = pack 'N', (scalar @_ / 2);
	while (my $name = shift) {
		my $value = shift;
		die 'No value' unless defined $value;
		$value = join "\x00", @$value if ref $value and ref $value eq 'ARRAY';
		$name_value .= pack 'N a* N a*',
			map { length $_ => $_ }
			(lc ($name) => $value);
	}
	return $name_value;
}

sub unpack_nv
{
	my $self = shift;
	my $buf = shift;
	my @retval;

	my $entries;
	my $name_value = $self->{compressor}->uncompress ($buf);

	($entries, $name_value) = unpack 'N a*', $name_value;
	foreach (1..$entries) {
		my $len;
		my $name;
		my $value;

		($len, $name_value) = unpack 'N a*', $name_value;
		($name, $name_value) = unpack "a$len a*", $name_value;

		($len, $name_value) = unpack 'N a*', $name_value;
		($value, $name_value) = unpack "a$len a*", $name_value;

		my @values = split /\x00/, $value;
		$value = [ @values ] if scalar @values > 1;

		push @retval, $name => $value;

	}

	return @retval;
}

=back

=cut

sub reliable_read
{
	my $handle = shift;
	my $length = shift;

	my $buf = '';
	while (length $buf < $length) {
		my $ret = $handle->read ($buf, $length - length $buf,
			length $buf);
		next if $!{EINTR};
		die 'Read error '.$! unless defined $ret;
		return '' if $ret == 0;
	}

	return $buf;
}

=head1 FRAME FORMATS

These are the data structures that are consumed by C<write_frame()> and
produced by C<read_frame()> methods. Their purpose is to coveniently represent
the fields of serialized SPDY frames. Please refer to the protocol
specification (L<SEE ALSO> section) for descriptions of the actual fields.

Not all fields are mandatory at all occassions. Serializer may assume sane
values for certain fields, that are marked as I<Input only> below, or provided
with defaults.

=over 4

=item SYN_STREAM

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::SYN_STREAM,
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for SYN_STREAM
      stream_id   => <stream_id>,
      associated_stream_id => <associated_stream_id>,

      priority    => <priority>,
      slot        => <slot>,

      headers     =>  [
          ':version'  => <version>,   # E.g. 'HTTP/1.1'
          ':scheme'   => <scheme>,    # E.g. 'https'
          ':host'     => <host>,      # E.g. 'example.net:443',
          ':method'   => <method>,    # E.g. 'GET', 'HEAD',...
          ':path'     => <path>,      # E.g. '/something',
          ... # HTTP headers, e.g. Accept => 'text/plain'
      ],
  )

=cut

sub write_syn_stream
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N c c a*',
		($frame{stream_id} & 0x7fffffff),
		($frame{associated_stream_id} & 0x7fffffff),
		($frame{priority} & 0x07) << 5,
		($frame{slot} & 0xff),
		$self->{compressor}->compress ($self->pack_nv (@{$frame{headers}}));

	return %frame;
}

sub read_syn_stream
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;

	($frame{stream_id}, $frame{associated_stream_id},
		$frame{priority}, $frame{slot}, $frame{headers}) =
		unpack 'N N c c a*', delete $frame{data};

	$frame{stream_id} &= 0x7fffffff;
	$frame{associated_stream_id} &= 0x7fffffff;
	$frame{priority} = ($frame{priority} & 0xe0) >> 5;
	$frame{slot} &= 0xff;
	$frame{headers} = [$self->unpack_nv ($frame{headers})];

	return %frame;
}

=item SYN_REPLY

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::SYN_REPLY,
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for SYN_REPLY
      stream_id   => <stream_id>,

      headers     =>  [
          ':version'  => <version>,   # E.g. 'HTTP/1.1'
          ':status'   => <status>,    # E.g. '500 Front Fell Off',
          ... # HTTP headers, e.g. 'Content-Type' => 'text/plain'
      ],
  )
=cut

sub write_syn_reply
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N a*',
		($frame{stream_id} & 0x7fffffff),
		$self->{compressor}->compress ($self->pack_nv (@{$frame{headers}}));

	return %frame;
}

sub read_syn_reply
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;

	($frame{stream_id}, $frame{headers}) =
		unpack 'N a*', delete $frame{data};
	$frame{headers} = [$self->unpack_nv ($frame{headers})];

	return %frame;
}

=item RST_STREAM

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::RST_STREAM
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for RST_STREAM
      stream_id   => <stream_id>,
      status      => <status>,
  )

=cut

sub write_rst_stream
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N',
		($frame{stream_id} & 0x7fffffff),
		$frame{status};

	return %frame;
}

sub read_rst_stream
{
	my $self = shift;
	my %frame = @_;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;
	die 'Mis-sized rst_stream frame'
		unless $frame{length} == 8;

	my $stream_id;
	($stream_id, $frame{status}) = unpack 'N N', delete $frame{data};
	$frame{stream_id} = ($stream_id & 0x7fffffff);

	return %frame;
}

=item SETTINGS

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::SYN_SETTINGS
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for SETTINGS
      entries     => <entries>,   # Input only

      id_values   =>  [
          {
              flags   => <flags>,
              id  => <id>,
              value   => <value>,
          },
          ...
      ],
  )

=cut

sub write_settings
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N', scalar @{$frame{id_values}};
	foreach my $entry (@{$frame{id_values}}) {
		$frame{data} .= pack 'N',
			($entry->{flags} & 0x000000ff) << 24 |
			($entry->{id} & 0x00ffffff);
		$frame{data} .= pack 'N', $entry->{value};
	}

	return %frame;
}

sub read_settings
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;

	($frame{entries}, $frame{data}) =
		unpack 'N a*', $frame{data};
	$frame{id_values} = [];

	foreach (1..$frame{entries}) {
		my %entry;
		my $head;
		($head, $entry{value}, $frame{data}) =
			unpack 'N N a*', $frame{data};
		$entry{id} = $head & 0x00ffffff;
		$entry{flags} = ($head & 0xff000000) >> 24;
		push @{$frame{id_values}}, \%entry;
	}
	delete $frame{data};

	return %frame;
}

=item PING

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::PING
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for PING
      id          => <id>,        # E.g. 0x706c6c6d
  )


=cut

sub write_ping
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N', $frame{id};

	return %frame;
}

sub read_ping
{
	my $self = shift;
	my %frame = @_;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;
	die 'Mis-sized ping frame'
		unless $frame{length} == 4;

	$frame{id} = unpack 'N', delete $frame{data};

	return %frame;
}

=item GOAWAY

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::GOAWAY
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for GOAWAY
      last_good_stream_id => <last_good_stream_id>,
      status      => <status>,
  )

=cut

sub write_goaway
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N',
		($frame{last_good_stream_id} & 0x7fffffff),
		$frame{status};

	return %frame;
}

sub read_goaway
{
	my $self = shift;
	my %frame = @_;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;
	die 'Mis-sized goaway frame'
		unless $frame{length} == 8;

	my $last_good_stream_id;
	($last_good_stream_id, $frame{status}) = unpack 'N N', delete $frame{data};
	$frame{last_good_stream_id} = ($last_good_stream_id & 0x7fffffff);

	return %frame;
}

=item HEADERS

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::HEADERS,
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for HEADERS
      stream_id   => <stream_id>,

      headers     =>  [
          ... # HTTP headers, e.g. Accept => 'text/plain'
      ],
  )

=cut

sub write_headers
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N a*',
		($frame{stream_id} & 0x7fffffff),
		$self->{compressor}->compress ($self->pack_nv (@{$frame{headers}}));

	return %frame;
}

sub read_headers
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;

	($frame{stream_id}, $frame{headers}) =
		unpack 'N a*', delete $frame{data};

	$frame{stream_id} &= 0x7fffffff;
	$frame{headers} = [$self->unpack_nv ($frame{headers})];

	return %frame;
}

=item WINDOW_UPDATE

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 3,           # Input only
      type        => Net::SPDY::Framer::WINDOW_UPDATE
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for WINDOW_UPDATE
      stream_id   => <stream_id>,
      delta_window_size => <delta_window_size>,
  )

=cut

sub write_window_update
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N',
		($frame{stream_id} & 0x7fffffff),
		($frame{delta_window_size} & 0x7fffffff);

	return %frame;
}

sub read_window_update
{
	my $self = shift;
	my %frame = @_;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 3;
	die 'Mis-sized window_update frame'
		unless $frame{length} == 8;

	my ($stream_id, $delta_window_size) = unpack 'N N', delete $frame{data};
	$frame{stream_id} = ($stream_id & 0x7fffffff);
	$frame{delta_window_size} = ($delta_window_size & 0x7fffffff);

	return %frame;
}

=item CREDENTIAL

  (
      # Common to control frames
      control     => 1,           # Input only
      version     => 1,           # Input only
      type        => Net::SPDY::Framer::CREDENTIAL
      flags       => <flags>,     # Defaults to 0
      length      => <length>,    # Input only

      # Specific for CREDENTIAL
      slot        => <slot>,
      proof       => <proof>,
      certificates => [ <certificate>, ... ],
  )

=cut

sub write_credential
{
	my $self = shift;
	my %frame = @_;

	$frame{version} ||= 1;
	$frame{data} = pack 'n N a*', $frame{slot},
		length $frame{proof}, $frame{proof};

	foreach my $credential (@{$frame{certificates}}) {
		$frame{data} .= pack 'N a*', length $credential,
			$credential;
	}

	return %frame;
}

sub read_credential
{
	my $self = shift;
	my %frame = @_;

	die 'Bad version '.$frame{version}
		unless $frame{version} == 1;

        my $len;
	($frame{slot}, $len, $frame{data}) = unpack 'n N a*', $frame{data};
	($frame{proof}, $frame{data}) = unpack "a$len a*", $frame{data};
	$frame{certificates} = [];

	while ($frame{data}) {
		my $credential;
		($len, $frame{data}) = unpack 'N a*', $frame{data};
		($credential, $frame{data}) = unpack "a$len a*", $frame{data};
		push @{$frame{certificates}}, $credential;
	}

	return %frame;
}

=back

=head1 METHODS

=over 4

=item new { socket => SOCKET, compressor => COMPRESSOR }

Creates a new framer instance. You need to create and pass both the socket for
the network communication and the compressor instance.

=cut

sub new
{
	my $class = shift;
	my $self = bless shift, $class;

	return $self;
}

=item write_frame FRAME

Serializes frame and writes it to the network socket.

=cut

sub write_frame
{
	my $self = shift;
	my %frame = @_;

	# Serialize the payload
	if ($frame{type}) {
		if ($frame{type} == SYN_STREAM) {
			%frame = $self->write_syn_stream (%frame);
		} elsif ($frame{type} == SYN_REPLY) {
			%frame = $self->write_syn_reply (%frame);
		} elsif ($frame{type} == RST_STREAM) {
			%frame = $self->write_rst_stream (%frame);
		} elsif ($frame{type} == SETTINGS) {
			%frame = $self->write_settings (%frame);
		} elsif ($frame{type} == PING) {
			%frame = $self->write_ping (%frame);
		} elsif ($frame{type} == GOAWAY) {
			%frame = $self->write_goaway (%frame);
		} elsif ($frame{type} == HEADERS) {
			%frame = $self->write_headers (%frame);
		} elsif ($frame{type} == WINDOW_UPDATE) {
			%frame = $self->write_window_update (%frame);
		} elsif ($frame{type} == CREDENTIAL) {
			%frame = $self->write_credential (%frame);
		} else {
			die 'Not implemented: Unsupported frame '.$frame{type};
		}

		$frame{control} = 1 unless exists $frame{control};
		$frame{version} = 3 unless exists $frame{version};
		$frame{flags} = 0 unless exists $frame{flags};
	}

	$frame{length} = length $frame{data};

	$self->{socket}->print (pack 'N', ($frame{control} ? (
		$frame{control} << 31 |
		$frame{version} << 16 |
		$frame{type}
	) : (
		$frame{stream_id}
	))) or die 'Short write';

	$self->{socket}->print (pack 'N', (
		$frame{flags} << 24 |
		$frame{length}
	)) or die 'Short write';

	if ($frame{data}) {
		$self->{socket}->print ($frame{data})
			or die "Short write $! $self->{socket}";
	}

	return %frame;
}

=item read_frame

Reads frame from the network socket and returns it deserialized.

=cut

sub read_frame
{
	my $self = shift;

	# First word of the frame header
	return () unless $self->{socket};
	my $buf = reliable_read ($self->{socket}, 4);
	die 'Short read' unless defined $buf;
	return () if $buf eq '';
	my $head = unpack 'N', $buf;
	my %frame = (control => ($head & 0x80000000) >> 31);

	if ($frame{control}) {
		$frame{version}	= ($head & 0x7fff0000) >> 16;
		$frame{type} = ($head & 0x0000ffff);
	} else {
		$frame{stream_id} = ($head & 0x7fffffff);
	};

	# Common parts of the header
	$buf = reliable_read ($self->{socket}, 4) or die 'Read error';
	my $body = unpack 'N', $buf;
	$frame{flags} = ($body & 0xff000000) >> 24;
	$frame{length} = ($body & 0x00ffffff);

	# Frame payload
	unless ($frame{length}) {
		$frame{data} = '';
		return %frame;
	}
	$frame{data} = reliable_read ($self->{socket}, $frame{length})
		or die 'Read error';

	# Grok the payload
	if ($frame{control}) {
		if ($frame{type} == SYN_STREAM) {
			%frame = $self->read_syn_stream (%frame);
		} elsif ($frame{type} == SYN_REPLY) {
			%frame = $self->read_syn_reply (%frame);
		} elsif ($frame{type} == RST_STREAM) {
			%frame = $self->read_rst_stream (%frame);
		} elsif ($frame{type} == SETTINGS) {
			%frame = $self->read_settings (%frame);
		} elsif ($frame{type} == PING) {
			%frame = $self->read_ping (%frame);
		} elsif ($frame{type} == GOAWAY) {
			%frame = $self->read_goaway (%frame);
		} elsif ($frame{type} == HEADERS) {
			%frame = $self->read_headers (%frame);
		} elsif ($frame{type} == WINDOW_UPDATE) {
			%frame = $self->read_window_update (%frame);
		} elsif ($frame{type} == CREDENTIAL) {
			%frame = $self->read_credential (%frame);
		} else {
			# We SHOULD ignore these, if we did implement everything
			# that we MUST implement.
			die 'Not implemented: Unsupported control frame '.$frame{type};
		}
	}

	return %frame;
}

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<http://www.chromium.org/spdy/spdy-protocol/spdy-protocol-draft3> -- Protocol specification

=item *

L<Net::SPDY::Session> -- SPDY session implementation

=item *

L<Net::SPDY::Compressor> -- SPDY header compression

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
