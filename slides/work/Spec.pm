package Spec;
# 共用：解析 outline.md / spec.md 的頁面區塊
use strict; use warnings; use utf8;
use Exporter 'import';
use Wiki qw(read_utf8);
our @EXPORT_OK = qw(parse_slides table_rows bullets);

# 回傳 [ { id, title, f => {欄位 => [值...]}, sec => {小節 => [行...]} } ]
sub parse_slides {
  my $file = shift;
  my (@S, $cur, $sec);
  for my $l (split /\n/, read_utf8($file)) {
    if ($l =~ /^## (S\d{2})\s+(.+)$/) { $cur = { id => $1, title => $2, f => {}, sec => {} }; $sec = undef; push @S, $cur; next; }
    if ($l =~ /^## /) { $cur = undef; next; }
    next unless $cur;
    if ($l =~ /^### (.+?)\s*$/) { $sec = $1; $cur->{sec}{$sec} //= []; next; }
    if (!defined $sec && $l =~ /^- ([^:：]+)[:：]\s*(.*)$/) { push @{$cur->{f}{$1}}, $2; next; }
    push @{$cur->{sec}{$sec}}, $l if defined $sec && $l =~ /\S/;
  }
  return @S;
}

sub table_rows {
  my @rows;
  for my $l (@_) {
    next unless $l =~ /^\|/;
    my $x = $l; $x =~ s/\\\|/\x{0}/g; $x =~ s/^\s*\|//; $x =~ s/\|\s*$//;
    my @c = map { (my $y = $_) =~ s/\x{0}/|/g; $y =~ s/^\s+|\s+$//g; $y } split /\|/, $x;
    next if $c[0] =~ /^-+$/ || $c[0] eq '標籤';
    push @rows, \@c;
  }
  return @rows;
}

sub bullets { map { (my $x = $_) =~ s/^-\s*//; $x } grep { /^- / } @_ }

1;
