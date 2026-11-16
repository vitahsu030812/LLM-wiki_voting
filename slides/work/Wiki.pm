package Wiki;
# 共用：讀取 wiki 頁面、frontmatter、別名、WikiLink
use strict; use warnings; use utf8;
use File::Find;
use File::Basename;
use Encode qw(decode);
use Exporter 'import';
our @EXPORT_OK = qw(load_wiki resolve read_utf8 norm_num norm_text);

sub read_utf8 {
  my ($p) = @_;
  open my $fh, '<:encoding(UTF-8)', $p or die "cannot read $p: $!";
  local $/; my $t = <$fh>; close $fh;
  $t =~ s/^\x{FEFF}//; $t =~ s/\r\n/\n/g;
  return $t;
}

sub type_of {
  my ($rel) = @_;
  return "cand-$1" if $rel =~ m{^candidates/([^/]+)/};
  return 'topic'      if $rel =~ m{^topics/};
  return 'election'   if $rel =~ m{^elections/};
  return 'overview'   if $rel =~ m{^overview/};
  return 'comparison' if $rel =~ m{^comparisons/};
  return 'lesson'     if $rel =~ m{^lessons/};
  return 'meta';
}

sub parse_fm {
  my ($t) = @_;
  my %fm;
  return \%fm unless $t =~ /\A---\n(.*?)\n---\n/s;
  my $key;
  for my $line (split /\n/, $1) {
    if ($line =~ /^([A-Za-z_]+):\s*(.*)$/) {
      $key = $1; my $v = $2; $v =~ s/\s+#.*$//; $v =~ s/^["']|["']$//g;
      $fm{$key} = ($v eq '' ? [] : $v);
    } elsif ($line =~ /^\s+-\s+(.*)$/ && $key) {
      my $v = $1; $v =~ s/^["']|["']$//g;
      $fm{$key} = [] unless ref $fm{$key};
      push @{$fm{$key}}, $v;
    }
  }
  return \%fm;
}

# 回傳 { pages => { stem => {...} }, names => { name/alias => stem } }
sub load_wiki {
  my ($root) = @_;
  my (%pages, %names);
  my $root_u = decode("UTF-8", $root);
  find({ no_chdir => 1, wanted => sub {
    return unless /\.md$/;
    my $p = $File::Find::name;
    my $pu = decode("UTF-8", $p);
    (my $rel = $pu) =~ s{^\Q$root_u\E/?}{};
    my $stem = basename($pu, '.md');
    my $t = read_utf8($p);
    my $fm = parse_fm($t);
    $pages{$stem} = { stem => $stem, path => $p, rel => $rel, type => type_of($rel), fm => $fm, text => $t };
    $names{$stem} = $stem;
  }}, $root);
  for my $s (keys %pages) {
    my $al = $pages{$s}{fm}{aliases};
    next unless ref $al;
    $names{$_} //= $s for @$al;
  }
  return { pages => \%pages, names => \%names };
}

sub resolve {
  my ($W, $name) = @_;
  $name =~ s/^\s+|\s+$//g;
  return $W->{names}{$name};
}

sub norm_num  { my $s = shift; $s =~ s/[,，\s]//g; return $s; }
sub norm_text { my $s = shift; $s =~ s/\*\*//g; $s =~ s/\s+//g; return $s; }

1;
