#!/usr/bin/perl
# 建立 wiki 知識圖譜：graph.json（機器用）＋ graph.md（人看）
# 用法：perl build_graph.pl [wiki 路徑，預設 ../../wiki]
use strict; use warnings; use utf8;
use FindBin; use lib $FindBin::Bin;
use JSON::PP;
use Wiki qw(load_wiki resolve);
binmode STDOUT, ':encoding(UTF-8)';

my $root = shift // "$FindBin::Bin/../../wiki";
my $W = load_wiki($root);
my $P = $W->{pages};
my $TEMPLATE_MIN = 20;   # 同一行連結文字出現在 ≥ 20 頁 → 視為樣板

my %RACE = ('cand-magistrate'=>'縣長','cand-mayor'=>'市長','cand-councilor'=>'縣議員','cand-rep'=>'市民代表','cand-li-chief'=>'里長');
my %NAVTYPE = map { $_ => 1 } qw(overview election meta lesson);   # 課程頁的連結屬導覽，不計入候選人關係

# ---- 收集連結 ----
my (@raw, %line_pages);
for my $s (sort keys %$P) {
  next if $s eq 'log';   # 操作日誌不算關係
  my $t = $P->{$s}{text};
  my ($fm_part) = $t =~ /\A(---\n.*?\n---\n)/s; $fm_part //= '';
  for my $line (split /\n/, $t) {
    while ($line =~ /\[\[([^\]\|#]+)(?:#[^\]\|]*)?(?:\|[^\]]*)?\]\]/g) {
      my $target = $1;
      (my $norm = $line) =~ s/^\s*[-*|]\s*//;
      push @raw, { from => $s, target => $target, line => $norm, in_fm => (index($fm_part, $line) >= 0 ? 1 : 0) };
      $line_pages{$norm}{$s} = 1;
    }
  }
}

my (@edges, %broken, %seen);
for my $r (@raw) {
  my $to = resolve($W, $r->{target});
  if (!defined $to) { $broken{$r->{target}}{$r->{from}} = 1; next; }
  next if $to eq $r->{from};
  my $kind;
  if    ($NAVTYPE{$P->{$to}{type}} || $P->{$r->{from}}{type} =~ /^(meta|lesson)$/) { $kind = 'nav' }
  elsif (keys %{$line_pages{$r->{line}}} >= $TEMPLATE_MIN)              { $kind = 'template' }
  else                                                                  { $kind = 'substantive' }
  my $k = "$r->{from}\t$to\t$kind";
  next if $seen{$k}++;
  push @edges, { from => $r->{from}, to => $to, kind => $kind };
}

# ---- 節點 ----
my @nodes;
for my $s (sort keys %$P) {
  my $fm = $P->{$s}{fm};
  my %n = (id => $s, type => $P->{$s}{type}, rel => $P->{$s}{rel});
  for my $k (qw(name party zone li election_number incumbent position district)) {
    $n{$k} = $fm->{$k} if defined $fm->{$k} && !ref $fm->{$k};
  }
  $n{race} = $RACE{$n{type}} if $RACE{$n{type}};
  push @nodes, \%n;
}
my %N = map { $_->{id} => $_ } @nodes;

open my $jf, '>:encoding(UTF-8)', "$FindBin::Bin/graph.json" or die;
print $jf JSON::PP->new->utf8(0)->canonical->pretty->encode({ nodes => \@nodes, edges => \@edges, broken => { map { $_ => [sort keys %{$broken{$_}}] } keys %broken } });
close $jf;

# ---- 摘要 ----
my (%deg_sub_in, %deg_sub_out, %tmpl_in);
for my $e (@edges) {
  if ($e->{kind} eq 'substantive') { $deg_sub_in{$e->{to}}++; $deg_sub_out{$e->{from}}++; }
  if ($e->{kind} eq 'template')    { $tmpl_in{$e->{to}}++; }
}
sub race_key { my $n = shift; my $k = $n->{race}; $k .= " 第$n->{zone}區" if $n->{zone}; $k .= " $n->{li}" if $n->{li}; return $k; }
sub num { my $v = shift // 99; $v =~ /(\d+)/ ? $1 : 99 }

my @md;
push @md, "# 知識圖譜摘要（自動產生，請勿手改）", "", "> 由 `build_graph.pl` 產生。wiki：`$root`", "";
my %tc; $tc{$_->{type}}++ for @nodes;
push @md, "## 1. 節點", "", "| 類型 | 數量 |", "|---|---|", (map { "| $_ | $tc{$_} |" } sort keys %tc), "";
my %ec; $ec{$_->{kind}}++ for @edges;
push @md, "## 2. 邊", "", "| 種類 | 數量 | 說明 |", "|---|---|---|",
  "| substantive | ".($ec{substantive}//0)." | 內容中的實質關係，用於大綱 |",
  "| template | ".($ec{template}//0)." | 同一行出現在 ≥ $TEMPLATE_MIN 頁的樣板連結，不計入關係 |",
  "| nav | ".($ec{nav}//0)." | 連到總覽／選舉結果／索引 |", "";

# 3. 選舉層級
push @md, "## 3. 選舉層級（章節骨架，依號次）", "";
my %byrace;
for my $n (@nodes) { push @{$byrace{race_key($n)}}, $n if $n->{race}; }
for my $rk (sort keys %byrace) {
  my @c = sort { num($a->{election_number}) <=> num($b->{election_number}) } @{$byrace{$rk}};
  push @md, "- **$rk**（".scalar(@c)." 人）：".join('、', map { num($_->{election_number}).' '.($_->{name}//$_->{id}).($_->{incumbent} && $_->{incumbent} eq 'true' ? '＊' : '') } @c);
}
push @md, "", "＊＝frontmatter 標記為現任", "";

# 4. 議題鄰居
push @md, "## 4. 議題節點與相關候選人（substantive，雙向）", "";
for my $t (grep { $_->{type} eq 'topic' } @nodes) {
  my %nb;
  for my $e (grep { $_->{kind} eq 'substantive' } @edges) {
    my $o = $e->{from} eq $t->{id} ? $e->{to} : $e->{to} eq $t->{id} ? $e->{from} : undef;
    next unless $o && $N{$o}{race};
    $nb{$N{$o}{race}}{$o} = 1;
  }
  push @md, "### $t->{id}";
  for my $r (sort keys %nb) { push @md, "- $r：".join('、', sort keys %{$nb{$r}}); }
  push @md, "";
}

# 5. 跨級關係
push @md, "## 5. 候選人之間的實質連結（跨選舉層級）", "";
my $cnt = 0;
for my $e (grep { $_->{kind} eq 'substantive' } @edges) {
  my ($a, $b) = ($N{$e->{from}}, $N{$e->{to}});
  next unless $a->{race} && $b->{race} && $a->{race} ne $b->{race};
  push @md, "- $a->{id} → $b->{id}"; $cnt++;
}
push @md, "- （無）" unless $cnt; push @md, "";

# 6. 樣板連結不對稱
push @md, "## 6. 樣板連結對稱性（同一選舉的候選人應一致）", "";
my $asym = 0;
for my $rk (sort keys %byrace) {
  my @c = @{$byrace{$rk}};
  my %v = map { ($tmpl_in{$_->{id}} // 0) => 1 } @c;
  next if keys %v <= 1;
  $asym++;
  push @md, "- ⚠ **$rk**：".join('、', map { "$_->{id}=".($tmpl_in{$_->{id}}//0) } sort { num($a->{election_number}) <=> num($b->{election_number}) } @c);
}
push @md, "- 全部一致" unless $asym; push @md, "";

# 7. 斷鏈
push @md, "## 7. 斷鏈（找不到目標頁）", "";
if (%broken) { push @md, map { "- [[$_]] ← ".join('、', sort keys %{$broken{$_}}) } sort keys %broken; }
else { push @md, "- 無"; }
push @md, "";

# 8. 孤立候選人
push @md, "## 8. 沒有任何實質連結的候選人", "";
my @iso = grep { $_->{race} && !$deg_sub_in{$_->{id}} && !$deg_sub_out{$_->{id}} } @nodes;
push @md, @iso ? (map { "- $_->{id}" } @iso) : ("- 無");
push @md, "";

open my $mf, '>:encoding(UTF-8)', "$FindBin::Bin/graph.md" or die;
print $mf join("\n", @md); close $mf;
printf "graph: %d nodes, %d edges (substantive %d / template %d / nav %d), broken %d, asym races %d, isolated %d\n",
  scalar(@nodes), scalar(@edges), $ec{substantive}//0, $ec{template}//0, $ec{nav}//0, scalar(keys %broken), $asym, scalar(@iso);
