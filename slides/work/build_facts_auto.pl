#!/usr/bin/perl
# 由 wiki 的結構化表格自動產生事實卡 → facts_auto.md（請勿手改，重跑即覆蓋）
#   R＊ 2026 名冊（2026年候選人彙整）
#   E＊ 2022 開票結果（2022年選舉結果）
#   P＊ 人口（員林市基本資料）
use strict; use warnings; use utf8;
use FindBin; use lib $FindBin::Bin;
use Wiki qw(load_wiki resolve);
binmode STDOUT, ':encoding(UTF-8)';

my $root = shift // "$FindBin::Bin/../../wiki";
my $W = load_wiki($root);
my @F;   # [id, key, value, page, snippet, source]
my %n;
sub add { my ($pfx, @r) = @_; push @F, [sprintf('%s%03d', $pfx, ++$n{$pfx}), @r]; }
sub cells { my $l = shift; $l =~ s/^\s*\|//; $l =~ s/\|\s*$//; return map { my $c = $_; $c =~ s/\*\*//g; $c =~ s/^\s+|\s+$//g; $c } split /\|/, $l; }
sub num { my $s = shift; $s =~ s/,//g; return $s; }
sub trimline { my $l = shift; $l =~ s/^\s+|\s+$//g; return $l; }

# ---------- R: 2026 名冊 ----------
{
  my $pg = '2026年候選人彙整'; my $t = $W->{pages}{resolve($W, $pg)}{text};
  my $src = '中選會 2026 候選人公告';
  my ($race, $zone) = ('', '');
  for my $l (split /\n/, $t) {
    if ($l =~ /^## .*縣長/)   { $race = '縣長'; $zone = ''; next }
    if ($l =~ /^## .*市長/)   { $race = '市長'; $zone = ''; next }
    if ($l =~ /^## .*縣議員/) { $race = '縣議員'; $zone = ''; next }
    if ($l =~ /^## .*市民代表/) { $race = '市民代表'; next }
    if ($l =~ /^### 第(\d+)選舉區/) { $zone = "第$1區"; next }
    if ($l =~ /^## .*里長/)   { $race = '里長'; next }
    if ($l =~ /^## /)         { $race = ''; next }
    next unless $race && $l =~ /^\|\s*\S/ && $l !~ /^\|[-\s|]+\|$/;
    my @c = cells($l);
    if ($race eq '里長') {
      next unless $c[2] =~ /^\d+$/;
      my ($li, $no, $nm, $pt) = @c[0,2,3,4];
      add('R', "名冊.里長.$li.$no", $nm, $pg, trimline($l), $src);
      add('R', "名冊.里長.$li.$no.政黨", $pt, $pg, trimline($l), $src);
    } else {
      next unless $c[0] =~ /^\d+$/;
      my $k = $zone ? "名冊.$race.$zone.$c[0]" : "名冊.$race.$c[0]";
      add('R', $k, $c[1], $pg, trimline($l), $src);
      add('R', "$k.政黨", $c[2], $pg, trimline($l), $src);
    }
  }
  if ($t =~ /(應選(\d+)席)/) { add('R', '2026.縣議員.應選席次', $2, $pg, $1, $src); }
}

# ---------- E: 2022 開票 ----------
{
  my $pg = '2022年選舉結果'; my $t = $W->{pages}{resolve($W, $pg)}{text};
  my $src = '中選會選舉及公投資料庫（db.cec.gov.tw）';
  my ($sec, $zone) = ('', '');
  for my $l (split /\n/, $t) {
    if ($l =~ /^## 一、/) { $sec = '縣長'; next }
    if ($l =~ /^## 二、/) { $sec = '縣議員'; next }
    if ($l =~ /^## 三、/) { $sec = '市長'; next }
    if ($l =~ /^## 四、/) { $sec = '市民代表'; next }
    if ($l =~ /^## 五、/) { $sec = '里長'; next }
    if ($l =~ /^## /)     { $sec = ''; next }
    next unless $sec;
    if ($sec eq '縣議員' && $l =~ /(應選席次\*\*：(\d+) 席)/) { add('E', '2022.縣議員.應選席次', $2, $pg, '應選席次：'.$2.' 席', $src); next }
    if ($sec eq '縣長' && $l =~ /^\|\s*\d/) {
      my @c = cells($l); add('E', "2022.縣長.$c[1].員林票", num($c[3]), $pg, trimline($l), $src);
      add('E', "2022.縣長.$c[1].員林得票率", $c[4], $pg, trimline($l), $src);
    }
    if ($sec eq '市長' && $l =~ /^\|\s*\d/) {
      my @c = cells($l); add('E', "2022.市長.$c[1].票", num($c[4]), $pg, trimline($l), $src);
      add('E', "2022.市長.$c[1].得票率", $c[5], $pg, trimline($l), $src);
      add('E', "2022.市長.$c[1].結果", $c[6], $pg, trimline($l), $src);
    }
    if ($sec eq '縣議員' && $l =~ /^\|\s*\d/) {
      my @c = cells($l);
      my ($yl) = $c[4] =~ /^([\d,]+)/; my ($tot) = $c[5] =~ /^([\d,]+)/;
      add('E', "2022.縣議員.$c[1].選區票", num($tot), $pg, trimline($l), $src);
      add('E', "2022.縣議員.$c[1].員林票", num($yl), $pg, trimline($l), $src);
      add('E', "2022.縣議員.$c[1].結果", ($c[6] =~ /當選/ ? '當選' : '落選'), $pg, trimline($l), $src);
    }
    if ($sec eq '市民代表') {
      if ($l =~ /^### 第0?(\d+)選舉區（應選(\d+)席）/) { $zone = "第$1區"; add('E', "2022.市民代表.$zone.應選席次", $2, $pg, trimline($l), $src); next }
      if ($l =~ /^- \*\*(\S+?)\*\*（[^）]*）：([\d,]+) 票/) { add('E', "2022.市民代表.$1.票", num($2), $pg, trimline($l), $src); add('E', "2022.市民代表.$1.結果", '當選', $pg, trimline($l), $src); next }
      if ($l =~ /^- \*落選\*：/) {
        while ($l =~ /([\x{4e00}-\x{9fff}]{2,4})（(?:[^，）]*，)?([\d,]+)票/g) {
          my ($nm, $v) = ($1, $2);
          add('E', "2022.市民代表.$nm.票", num($v), $pg, trimline($l), $src);
          add('E', "2022.市民代表.$nm.結果", '落選', $pg, trimline($l), $src);
        }
      }
    }
    if ($sec eq '里長' && $l =~ /^\|\s*\*\*(\S+?里)\*\*\s*\|\s*\*\*(\S+?)\*\*\s*\(([\d,]+)票 \/ ([\d.]+%)\)/) {
      add('E', "2022.里長.$1.當選人", $2, $pg, trimline($l), $src);
      add('E', "2022.里長.$1.當選票", num($3), $pg, trimline($l), $src);
      add('E', "2022.里長.$1.當選得票率", $4, $pg, trimline($l), $src);
      my $li = $1; my @c = cells($l);
      while ($c[2] =~ /([\x{4e00}-\x{9fff}]{2,4}) \(([\d,]+)票/g) {
        add('E', "2022.里長.$li.落選.$1.票", num($2), $pg, trimline($l), $src);
      }
    }
  }
}

# ---------- P: 人口 ----------
{
  my $pg = '員林市基本資料'; my $t = $W->{pages}{resolve($W, $pg)}{text};
  my $src = '員林戶政事務所人口統計（2025）';
  if ($t =~ /(約 ([\d,]+) 人（2025年資料）)/) { add('P', '員林.總人口', num($2), $pg, $1, $src); }
  if ($t =~ /(\| 里數 \| (\d+) 里 \|)/)        { add('P', '員林.里數', $2, $pg, $1, $src); }
  for my $l (split /\n/, $t) {
    next unless $l =~ /^\|\s*(\d+)\s*\|\s*(\S+里)\s*\|\s*([\d,]+)\s*\|/;
    add('P', "人口.$2", num($3), $pg, trimline($l), $src);
    add('P', "人口排名.$2", $1, $pg, trimline($l), $src);
  }
}

# ---------- I: index.md 候選人一行摘要 ----------
{
  my $pg = 'index'; my $t = $W->{pages}{resolve($W, $pg)}{text};
  my $src = 'wiki 索引摘要';
  for my $l (split /\n/, $t) {
    next unless $l =~ /^\|\s*\[\[([^\]]+)\]\]\s*\|/;
    my @c = cells($l);
    (my $stem = $c[0]) =~ s/^\[\[|\]\]$//g;
    next unless $c[2] && $c[2] =~ /^\d+$/;
    add('I', "索引.$stem.政黨", $c[1], $pg, trimline($l), $src);
    add('I', "索引.$stem.號次", $c[2], $pg, trimline($l), $src);
    add('I', "索引.$stem.摘要", $c[3], $pg, trimline($l), $src);
  }
}

# ---------- 輸出 ----------
my @out = ("# 自動事實卡（由 build_facts_auto.pl 產生，請勿手改）", "",
  "| ID | 鍵 | 值 | 出處頁 | 原文片段 | 原始來源 |", "|----|----|----|--------|----------|----------|");
for my $f (@F) { push @out, '| '.join(' | ', map { (my $x = $_) =~ s/\|/\\|/g; $x } @$f).' |'; }
open my $o, '>:encoding(UTF-8)', "$FindBin::Bin/facts_auto.md" or die;
print $o join("\n", @out), "\n"; close $o;
my %c; $c{substr($_->[0],0,1)}++ for @F;
print "facts_auto: ".scalar(@F)." cards (".join(', ', map { "$_=$c{$_}" } sort keys %c).")\n";
