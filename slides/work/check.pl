#!/usr/bin/perl
# 檢查關卡：perl check.pl A|B|C|D|all
# 結束碼：0 通過、1 有 ERROR、2 關卡尚未實作
use strict; use warnings; use utf8;
use FindBin; use lib $FindBin::Bin;
use JSON::PP;
use Wiki qw(load_wiki resolve read_utf8 norm_num norm_text);
use Spec qw(parse_slides table_rows);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $DIR  = $FindBin::Bin;
my $ROOT = "$DIR/../../wiki";
my $gate = uc(shift // 'all');
# 簡報種類：voter＝選民參考簡報（預設）；lesson＝選前小教學（檔案在 lesson/）
my $DECK = lc($ENV{DECK} // 'voter');
die "DECK 只能是 voter 或 lesson\n" unless $DECK =~ /^(voter|lesson)$/;
my $DD   = $DECK eq 'lesson' ? "$DIR/lesson" : $DIR;
my $HTML_DEFAULT = $DECK eq 'lesson' ? "$DIR/../2026員林市選舉-選前小教學.html" : "$DIR/../2026員林市選舉-選民參考簡報.html";
print "deck: $DECK\n";
my (@ERR, @WARN);
sub err  { push @ERR,  "[$_[0]] $_[1]" }
sub warn_ { push @WARN, "[$_[0]] $_[1]" }

# ---------- 共用載入 ----------
system($^X, "$DIR/build_graph.pl") == 0 or die "build_graph 失敗\n";
system($^X, "$DIR/build_facts_auto.pl") == 0 or die "build_facts_auto 失敗\n";
my $W = load_wiki($ROOT);
my $G = JSON::PP->new->decode(read_utf8("$DIR/graph.json"));
my %NODE = map { $_->{id} => $_ } @{$G->{nodes}};

sub load_facts {
  my @f;
  my @files = ("$DIR/facts_auto.md", "$DIR/facts.md");
  push @files, "$DD/facts.md" if $DECK eq 'lesson';
  for my $file (@files) {
    next unless -e $file;
    (my $short = $file) =~ s{.*/}{};
    $short = "lesson/$short" if $file =~ m{/lesson/};
    my $ln = 0;
    for my $l (split /\n/, read_utf8($file)) {
      $ln++;
      next unless $l =~ /^\|\s*([A-Z]\d{3})\s*\|/;
      my $x = $l; $x =~ s/\\\|/\x{0}/g; $x =~ s/^\s*\|//; $x =~ s/\|\s*$//;
      my @c = map { (my $y = $_) =~ s/\x{0}/|/g; $y =~ s/^\s+|\s+$//g; $y } split /\|/, $x;
      push @f, { id => $c[0], key => $c[1], val => $c[2], page => $c[3], snip => $c[4], src => $c[5], file => "$short:$ln" };
    }
  }
  return @f;
}
my @FACTS = load_facts();
my (%BYID, %BYKEY);
for my $f (@FACTS) { $BYID{$f->{id}} //= $f; push @{$BYKEY{$f->{key}}}, $f; }
sub numval { my $v = shift // ''; $v =~ s/[,%\s]//g; return $v =~ /^-?\d+(\.\d+)?$/ ? $v : undef; }

my $RACE_RE = qr/^(縣長|市長|縣議員|市民代表|里長)$/;
sub roster_key {
  my $n = shift;
  my $no = $n->{election_number} // ''; $no =~ s/\D//g;
  return undef unless $n->{race} && $no ne '';
  return "名冊.里長.$n->{li}.$no" if $n->{race} eq '里長';
  return "名冊.市民代表.第$n->{zone}區.$no" if $n->{race} eq '市民代表';
  return "名冊.$n->{race}.$no";
}

# =================== 關卡 A：事實卡 ===================
sub gate_A {
  my %seen;
  for my $f (@FACTS) {
    err('A', "$f->{file} ID 重複：$f->{id}") if $seen{$f->{id}}++;
    for my $k (qw(key val page snip)) { err('A', "$f->{file} $f->{id} 欄位「$k」空白") unless defined $f->{$k} && $f->{$k} ne ''; }
    next unless defined $f->{snip};
    if ($f->{page} eq '計算') { check_formula($f); next; }
    my $stem = resolve($W, $f->{page});
    if (!$stem) { err('A', "$f->{id} 出處頁不存在：$f->{page}"); next; }
    my $pt = norm_text($W->{pages}{$stem}{text});
    my $sn = norm_text($f->{snip});
    if (index($pt, $sn) < 0) { err('A', "$f->{id} 原文片段不在「$f->{page}」中：$f->{snip}"); next; }
    my $v = norm_text($f->{val});
    my $ok = index($sn, $v) >= 0 || index(norm_num($sn), norm_num($v)) >= 0;
    err('A', "$f->{id} 值「$f->{val}」不在原文片段中") unless $ok;
  }
  # 同鍵不同值
  for my $k (sort keys %BYKEY) {
    my %v = map { norm_num(norm_text($_->{val})) => 1 } @{$BYKEY{$k}};
    err('A', "鍵「$k」有 ".scalar(keys %v)." 個不同的值：".join('、', map { "$_->{id}=$_->{val}" } @{$BYKEY{$k}})) if keys %v > 1;
  }
  # 覆蓋
  for my $need ('名冊.縣長', '名冊.市長', '名冊.縣議員', '名冊.市民代表', '名冊.里長', '2022.縣長', '2022.市長', '2022.縣議員', '2022.市民代表', '2022.里長', '議題.長者', '議題.交通', '議題.排水', '人口.') {
    err('A', "缺少「$need」類事實卡") unless grep { index($_, $need) == 0 } keys %BYKEY;
  }
  # 名冊 ↔ 候選人頁 frontmatter ↔ 索引
  my %covered;
  for my $n (grep { $_->{race} } values %NODE) {
    my $rk = roster_key($n);
    if (!$rk || !$BYKEY{$rk}) { err('A', "$n->{id}：名冊中找不到對應（".($rk // '缺號次').'）'); next; }
    $covered{$rk} = 1;
    my $rname = $BYKEY{$rk}[0]{val};
    my $nm = $n->{name} // '';
    err('A', "$n->{id}：頁面姓名「$nm」≠ 名冊「$rname」") if $nm ne $rname;
    my $rp = $BYKEY{"$rk.政黨"} ? $BYKEY{"$rk.政黨"}[0]{val} : '';
    err('A', "$n->{id}：頁面政黨「".($n->{party}//'')."」≠ 名冊「$rp」") if $rp && ($n->{party}//'') ne $rp;
    if (my $ip = $BYKEY{"索引.$n->{id}.政黨"}) { err('A', "$n->{id}：索引政黨「$ip->[0]{val}」≠ 名冊「$rp」") if $rp && $ip->[0]{val} ne $rp; }
    if (my $in = $BYKEY{"索引.$n->{id}.號次"}) { (my $no = $n->{election_number}) =~ s/\D//g; err('A', "$n->{id}：索引號次 $in->[0]{val} ≠ 頁面號次 $no") if $in->[0]{val} ne $no; }
  }
  for my $k (grep { /^名冊\.[^.]+(\.[^.]+)?\.\d+$/ } keys %BYKEY) { err('A', "名冊 $k（$BYKEY{$k}[0]{val}）沒有候選人頁面") unless $covered{$k}; }
  # 索引摘要中的 2022 票數 ↔ 開票結果
  for my $k (grep { /^索引\..+\.摘要$/ } keys %BYKEY) {
    my $f = $BYKEY{$k}[0]; (my $stem = $k) =~ s/^索引\.|\.摘要$//g; (my $nm = $stem) =~ s/-.*//;
    my %known = map { norm_num($_->{val}) => 1 } grep { $_->{key} =~ /^2022\..*\Q$nm\E\./ } @FACTS;
    while ($f->{val} =~ /([\d,]{3,})\s*票/g) {
      my $v = norm_num($1);
      warn_('A', "$stem 摘要寫 $1 票，但 2022 開票結果中找不到 $nm 的這個票數") unless $known{$v};
    }
  }
  # 知識圖譜
  for my $b (sort keys %{$G->{broken}}) { warn_('A', "斷鏈 [[$b]] ← ".join('、', @{$G->{broken}{$b}})); }
  my (%tin, %grp);
  $tin{$_->{to}}++ for grep { $_->{kind} eq 'template' } @{$G->{edges}};
  for my $n (grep { $_->{race} } @{$G->{nodes}}) { my $g = $n->{race}.($n->{zone} ? "第$n->{zone}區" : '').($n->{li} // ''); push @{$grp{$g}}, $n; }
  for my $g (sort keys %grp) {
    my %v = map { ($tin{$_->{id}} // 0) => 1 } @{$grp{$g}};
    warn_('A', "樣板連結不對稱（$g）：".join('、', map { "$_->{id}=".($tin{$_->{id}}//0) } @{$grp{$g}})) if keys %v > 1;
  }
}

sub check_formula {
  my $f = shift;
  my $e = $f->{snip};
  unless ($e =~ s/^=//) { err('A', "$f->{id} 算式需以 = 開頭"); return; }
  my $got;
  if ($e =~ /^count:(.*)$/) {
    my @ids = split /\s*,\s*/, $1;
    for (@ids) {
      if (/^\{(.+)\}$/) { err('A', "$f->{id} 計數引用不存在的鍵 $1") unless $BYKEY{$1}; }
      else              { err('A', "$f->{id} 計數引用不存在的卡 $_") unless $BYID{$_}; }
    }
    $got = scalar @ids;
  } else {
    my $bad = 0;
    $e =~ s/\{([^}]+)\}/ my $k = $1; my $c = $BYKEY{$k}; my $v = $c ? numval($c->[0]{val}) : undef; if (!defined $v) { err('A', "$f->{id} 算式引用的鍵不存在或非數值：$k"); $bad = 1; 0 } else { $v } /ge;
    return if $bad;
    if ($e !~ /^[\d.+\-*\/() ]+$/) { err('A', "$f->{id} 算式含不允許字元：$e"); return; }
    $got = eval $e;
  }
  my $want = numval($f->{val});
  if (!defined $want) { err('A', "$f->{id} 計算卡的值不是數字"); return; }
  my ($dec) = $want =~ /\.(\d+)$/; my $p = $dec ? length $dec : 0;
  my $g = sprintf("%.${p}f", $got);
  err('A', "$f->{id} 計算結果 $g ≠ 卡上的值 $f->{val}") if $g != $want;
}

# =================== 關卡 B：大綱 ===================
my %CHART = map { $_ => 1 } qw(cover column hbar grouped stacked donut matrix timeline units directory li-chart checklist colophon network flow goals quiz cards);
sub gate_B {
  my $file = "$DD/outline.md";
  unless (-e $file) { err('B', 'outline.md 不存在'); return; }
  my @S; my $cur;
  for my $l (split /\n/, read_utf8($file)) {
    if ($l =~ /^## (S\d{2})\s+(.+)$/) { $cur = { id => $1, title => $2, f => {} }; push @S, $cur; next; }
    next unless $cur && $l =~ /^- ([^:：]+)[:：]\s*(.*)$/;
    push @{$cur->{f}{$1}}, $2;
  }
  err('B', '大綱沒有任何頁面') unless @S;
  my ($min, $max) = $DECK eq 'lesson' ? (14, 28) : (12, 22);
  err('B', "總頁數 ".scalar(@S)." 不在 $min–$max 之間") if @S && (@S < $min || @S > $max);
  my (%covered_grp, %topic_seen, %id_seen);
  my $i = 0;
  for my $s (@S) {
    $i++;
    err('B', "$s->{id} 編號不連續（應為 S".sprintf('%02d', $i).'）') if $s->{id} ne sprintf('S%02d', $i);
    err('B', "$s->{id} 重複") if $id_seen{$s->{id}}++;
    for my $req (qw(章節 主張 圖型 來源類型)) {
      my $n = scalar @{$s->{f}{$req} // []};
      err('B', "$s->{id} 「$req」應有 1 行，目前 $n 行") if $n != 1;
    }
    my $claim = $s->{f}{主張}[0] // '';
    err('B', "$s->{id} 主張超過 40 字（".length($claim)."）") if length($claim) > 40;
    err('B', "$s->{id} 主張含多個句子") if $claim =~ /[。；;].+/;
    my $ct = $s->{f}{圖型}[0] // '';
    err('B', "$s->{id} 圖型「$ct」不在允許清單（".join(' ', sort keys %CHART)."）") unless $CHART{$ct};
    for my $nl (@{$s->{f}{節點} // []}) {
      while ($nl =~ /\[\[([^\]]+)\]\]/g) {
        my $st = resolve($W, $1);
        if (!$st) { err('B', "$s->{id} 節點不存在：[[$1]]"); next; }
        $topic_seen{$st} = 1 if $NODE{$st} && $NODE{$st}{type} eq 'topic';
      }
    }
    for my $fl (@{$s->{f}{事實} // []}) {
      for my $ref (split /\s*[,，]\s*/, $fl) {
        next if $ref eq '' || $ref eq '—';
        if ($ref =~ /^\{(.+?)(\*)?\}$/) {
          my ($k, $wild) = ($1, $2);
          my $ok = $wild ? (grep { index($_, $k) == 0 } keys %BYKEY) : $BYKEY{$k};
          err('B', "$s->{id} 事實鍵不存在：$ref") unless $ok;
        } elsif (!$BYID{$ref}) { err('B', "$s->{id} 事實卡不存在：$ref"); }
      }
    }
    for my $cv (@{$s->{f}{涵蓋} // []}) { $covered_grp{$_} = 1 for split /\s*[,，]\s*/, $cv; }
  }
  # 教學簡報：每一課（wiki/lessons 中有 lesson 編號的頁面）都要有「學習目標」與「小測驗」頁
  if ($DECK eq 'lesson') {
    my %need = map { $_->{fm}{lesson} => $_->{stem} } grep { $_->{type} eq 'lesson' && defined $_->{fm}{lesson} && !ref $_->{fm}{lesson} } values %{$W->{pages}};
    my (%has_goal, %has_quiz);
    for my $s (@S) {
      my ($no) = ($s->{f}{章節}[0] // '') =~ /^第(\d+)課/ or next;
      my $ct = $s->{f}{圖型}[0] // '';
      $has_goal{$no} = 1 if $ct eq 'goals';
      $has_quiz{$no} = 1 if $ct eq 'quiz';
    }
    for my $no (sort { $a <=> $b } keys %need) {
      err('B', "第${no}課（$need{$no}）沒有學習目標頁（圖型 goals、章節 第${no}課）") unless $has_goal{$no};
      err('B', "第${no}課（$need{$no}）沒有小測驗頁（圖型 quiz、章節 第${no}課）") unless $has_quiz{$no};
    }
    printf "B: %d 頁，課程 %d 課（目標頁 %d、測驗頁 %d）\n", scalar(@S), scalar(keys %need), scalar(grep { $need{$_} } keys %has_goal), scalar(grep { $need{$_} } keys %has_quiz);
    return;
  }
  # 每個選舉群組都要被完整涵蓋（列出全部候選人）
  my %grp;
  for my $n (grep { $_->{race} } @{$G->{nodes}}) { my $g = $n->{race}.($n->{zone} ? "第$n->{zone}區" : '').($n->{li} ? $n->{li} : ''); $grp{$g}++; }
  for my $g (sort keys %grp) {
    my ($race) = $g =~ /^(縣長|市長|縣議員|市民代表|里長)/;
    err('B', "沒有任何頁面完整列出「$g」的 $grp{$g} 位候選人（請在「涵蓋」寫 $g 或 $race）") unless $covered_grp{$g} || $covered_grp{$race};
  }
  for my $t (grep { $_->{type} eq 'topic' } @{$G->{nodes}}) { err('B', "議題「$t->{id}」沒有出現在任何頁面的節點") unless $topic_seen{$t->{id}}; }
  printf "B: %d 頁，涵蓋 %d/%d 個選舉群組，議題 %d/%d\n", scalar(@S), scalar(grep { $covered_grp{$_} || $covered_grp{($_ =~ /^(縣長|市長|縣議員|市民代表|里長)/)[0]} } keys %grp), scalar(keys %grp), scalar(keys %topic_seen), scalar(grep { $_->{type} eq 'topic' } @{$G->{nodes}});
}

# 解析一個事實引用 → (數值或文字, [事實物件...])；失敗回傳 undef
sub resolve_ref {
  my $r = shift;
  if ($r =~ /^[FDL]\d{3}$|^[REIP]\d{3}$/) { my $f = $BYID{$r} or return; return ($f->{val}, [$f]); }
  # #課:頁名 → 值必須逐字出現在該 wiki 課程頁（教學簡報用）
  if ($r =~ /^#課:(.+)$/) {
    my $st = resolve($W, $1) or return;
    return unless ($W->{pages}{$st}{type} // '') eq 'lesson';
    return (undef, [{ id => $r, val => '', snip => $W->{pages}{$st}{text} }]);
  }
  if ($r =~ /^\{(.+?)\*\}$/) { my $p = $1; my @f = map { @{$BYKEY{$_}} } grep { index($_, $p) == 0 } keys %BYKEY; return @f ? (undef, \@f) : (); }
  if ($r =~ /^\{(.+)\}$/)    { my $c = $BYKEY{$1} or return; return ($c->[0]{val}, $c); }
  if ($r =~ /^#re:(.+)$/)    { my $re = eval { qr/$1/ } or return; return (scalar(grep { /$re/ } keys %BYKEY), []); }
  if ($r =~ /^#rev:(.+)=(.+)$/) { my ($p, $v) = ($1, $2); my $re = eval { qr/$p/ } or return; return (scalar(grep { /$re/ && $BYKEY{$_}[0]{val} eq $v } keys %BYKEY), []); }
  if ($r =~ /^#nb:(.+)@(.+)$/) {
    my ($t, $race) = ($1, $2); my $ts = resolve($W, $t) or return;
    my %o;
    for my $e (grep { $_->{kind} eq 'substantive' } @{$G->{edges}}) {
      my $x = $e->{from} eq $ts ? $e->{to} : $e->{to} eq $ts ? $e->{from} : next;
      $o{$x} = 1 if ($NODE{$x}{race} // '') eq $race;
    }
    return (scalar(keys %o), []);
  }
  if ($r =~ /^#graph:type=(.+)$/) { my $ty = $1; return (scalar(grep { $_->{type} eq $ty } @{$G->{nodes}}), []); }
  return;
}
sub numbers_in { my $s = shift // ''; my @n; while ($s =~ /(\d[\d,]*(?:\.\d+)?)/g) { push @n, norm_num($1); } return @n; }

# =================== 關卡 C：逐頁規格 ===================
my @BANNED = qw(最好 最佳 最強 優秀 出色 可惜 惜敗 黑手 更上一層樓 強勢 亮眼 政二代 型男 正妹 高顏值 值得 推薦 首選 捲土重來);
my %SYM = map { $_ => 1 } ('●', '○', '△', '—');
sub gate_C {
  my $sf = "$DD/spec.md";
  unless (-e $sf) { err('C', 'spec.md 不存在'); return 0; }
  my @O = parse_slides("$DD/outline.md");
  my %O = map { $_->{id} => $_ } @O;
  my @S = parse_slides($sf);
  my %Sid = map { $_->{id} => 1 } @S;
  for my $o (@O) { err('C', "大綱的 $o->{id}「$o->{title}」在規格中不存在") unless $Sid{$o->{id}}; }
  # 名冊：姓名 → [群組, 號次]
  my %ROST;
  for my $k (grep { /^名冊\.(.+)\.(\d+)$/ } keys %BYKEY) { $k =~ /^名冊\.(.+)\.(\d+)$/; $ROST{$BYKEY{$k}[0]{val}} = [$1, $2]; }
  my $nrows = 0;
  for my $s (@S) {
    my $id = $s->{id}; my $o = $O{$id};
    if (!$o) { err('C', "$id 不在大綱中"); next; }
    my $claim = $s->{f}{主張}[0] // '';
    err('C', "$id 主張與大綱不同（大綱：$o->{f}{主張}[0]）") if $claim ne ($o->{f}{主張}[0] // '');
    err('C', "$id 圖型與大綱不同") if ($s->{f}{圖型}[0] // '') ne ($o->{f}{圖型}[0] // '');
    my $lay = $s->{f}{版面}[0] // '';
    err('C', "$id 版面需為 圖 60／文 40（目前：$lay）") unless $lay =~ /60/ && $lay =~ /40/;
    my $ord = $s->{f}{依號次}[0] // '';
    err('C', "$id 依號次需為 是／組內／否") unless $ord =~ /^(是|組內|否)$/;

    # 允許出現的數字：大綱事實＋引用＋圖表
    my (%allow, @refs);
    push @refs, map { split /\s*[,，]\s*/ } @{$o->{f}{事實} // []};
    push @refs, map { (my $x = $_) =~ s/^-\s*//; split /\s*,\s*/, $x } @{$s->{sec}{引用} // []};
    my $add_allow = sub { my ($v, $fs) = @_; $allow{$_} = 1 for numbers_in($v); for my $f (@{$fs // []}) { $allow{$_} = 1 for numbers_in($f->{val}); } };
    for my $r (@refs) { next if $r eq '' || $r eq '—'; my ($v, $fs) = resolve_ref($r); if (!$fs) { err('C', "$id 引用無法解析：$r"); next; } $add_allow->($v, $fs); }

    # 圖表資料
    my @rows = table_rows(@{$s->{sec}{圖表資料} // []});
    err('C', "$id 沒有圖表資料") unless @rows;
    my (@order, $text_all);
    $text_all = join(' ', map { "$_->[0] $_->[1]" } @rows);
    for my $r (@rows) {
      $nrows++;
      my ($lab, $val, $ref, $tag, $tref) = @$r;
      $ref //= '';
      if ($ref eq '說明') { (my $v2 = $val) =~ s/(?<!\d)(19|20)\d\d(?!\d)//g; err('C', "$id「$lab」標為說明卻含數字：$val") if $v2 =~ /\d/; next; }
      if ($ref eq '—')    { err('C', "$id「$lab」事實為 — 時值也必須是 —") unless $val eq '—'; next; }
      my ($fv, $fs) = resolve_ref($ref);
      if (!$fs) { err('C', "$id「$lab」事實無法解析：$ref"); next; }
      $add_allow->($val, $fs); $add_allow->($fv, []);
      unless ($SYM{$val}) {
        my $nv = numval($val);
        if (defined $nv && defined numval($fv)) {
          err('C', "$id「$lab」值 $val ≠ 事實 $ref 的值 $fv") if $nv != numval($fv);
        } else {
          my $hay = norm_text(join(' ', $fv // '', map { "$_->{val} $_->{snip}" } @$fs));
          err('C', "$id「$lab」值「$val」在事實 $ref 中找不到") if index($hay, norm_text($val)) < 0;
        }
      }
      if (defined $tag && $tag ne '') {
        my ($tv, $tfs) = resolve_ref($tref // '');
        if (!$tfs) { err('C', "$id「$lab」標記事實無法解析：".($tref // '')); }
        elsif (index(norm_text($tv // ''), norm_text($tag)) < 0) { err('C', "$id「$lab」標記「$tag」不在 $tref 的值中（$tv）"); }
      }
      # 依號次：取該列第一個出現的候選人姓名
      my $txt = "$lab $val";
      my ($best, $pos);
      for my $nm (keys %ROST) { my $p = index($txt, $nm); next if $p < 0; ($best, $pos) = ($nm, $p) if !defined $pos || $p < $pos || ($p == $pos && length $nm > length $best); }
      # 標籤中的號次（「群組｜數字」）必須等於該候選人的實際號次
      if ($best && $ref !~ /^\{2022\./ && $lab =~ /｜(\d{1,2})(?:｜|$)/) {
        err('C', "$id「$lab」標的號次 $1 ≠ $best 的實際號次 $ROST{$best}[1]") if $1 != $ROST{$best}[1];
      }
      # 2022 歷史資料列不參與 2026 號次排序
      if ($best && $ref !~ /^\{2022\./) { my ($grp) = $lab =~ /^([^｜]+)｜/; push @order, [$grp // '', $best]; }
    }
    # 由圖表資料可直接數出的數：各組列數、各組各標記列數、各標記列數、總列數、組數
    {
      my (%gc, %gt, %tc);
      for my $r (@rows) { my ($g) = $r->[0] =~ /^([^｜]+)｜/; $g //= ''; $gc{$g}++; if (defined $r->[3] && $r->[3] ne '') { $gt{"$g\t$r->[3]"}++; $tc{$r->[3]}++; } }
      $allow{$_} = 1 for values %gc, values %gt, values %tc, scalar(@rows), scalar(keys %gc), 1;
    }
    if ($ord eq '是' || $ord eq '組內') {
      my (%last, %seen);
      for my $x (@order) {
        my ($grp, $nm) = @$x; next if $seen{"$grp\t$nm"}++;
        my ($rg, $no) = @{$ROST{$nm}};
        my $k = ($ord eq '是' ? '' : $grp)."\t$rg";
        err('C', "$id 號次順序錯誤：$nm（$no 號）排在 $last{$k}[0]（$last{$k}[1] 號）之後") if $last{$k} && $no < $last{$k}[1];
        $last{$k} = [$nm, $no];
      }
    }
    # 涵蓋：選舉群組的每一位候選人都要出現在圖表
    for my $cv (@{$o->{f}{涵蓋} // []}) {
      for my $g (split /\s*[,，]\s*/, $cv) {
        my ($race, $sub) = $g =~ /^(縣長|市長|縣議員|市民代表|里長)(.*)$/;
        for my $nm (sort keys %ROST) {
          my $rg = $ROST{$nm}[0];
          next unless $rg =~ /^\Q$race\E/ && (!$sub || $rg =~ /\Q$sub\E/);
          err('C', "$id 涵蓋「$g」但圖表缺少 $nm") if index($text_all, $nm) < 0;
        }
      }
    }
    # 條列
    my @b = map { (my $x = $_) =~ s/^-\s*//; $x } grep { /^- / } @{$s->{sec}{條列} // []};
    err('C', "$id 條列 ".scalar(@b)." 點（應 3–7 點）") if @b < 3 || @b > 7;
    my $tot = 0;
    for my $b (@b) {
      $tot += length $b;
      err('C', "$id 條列超過 48 字：$b") if length($b) > 48;
    }
    err('C', "$id 條列合計 $tot 字，超過 240") if $tot > 240;
    # 禁用評價詞（引號內原文除外）
    for my $t (@b, $claim, @{$s->{f}{圖說} // []}, map { $_->[0] } @rows) {
      (my $x = $t) =~ s/「[^」]*」//g;
      for my $w (@BANNED) { err('C', "$id 含評價性字詞「$w」：$t") if index($x, $w) >= 0; }
    }
    # 數字溯源
    for my $t (@b, $claim, @{$s->{f}{圖說} // []}) {
      (my $x = $t) =~ s/\d{4}-\d{2}-\d{2}//g;
      $x =~ s/\bS\d\d\b//g;
      $x =~ s/第\s*\d+\s*(選舉區|選區|區|屆)?//g;
      $x =~ s/\d+\s*(號|區|屆)//g;
      $x =~ s/^\d+\s+(?=\S)//;
      while ($x =~ /(\d[\d,]*(?:\.\d+)?)(\s*%)?/g) {
        my ($raw, $pct) = ($1, $2);
        my $n = norm_num($raw);
        next if $n =~ /^(19|20)\d\d$/ && $raw !~ /,/;
        next if $allow{$n};
        my $strong = length($n) >= 3 || $raw =~ /[,.]/ || $pct;
        ($strong ? \&err : \&warn_)->('C', "$id 數字「$raw」在本頁引用的事實中找不到：$t");
      }
    }
    err('C', "$id 沒有來源") unless grep { /^- \S/ } @{$s->{sec}{來源} // []};
  }
  printf "C: %d 頁、%d 列圖表資料\n", scalar(@S), $nrows;
  return 0;
}
# =================== 關卡 D：HTML 成品 ===================
my %PALETTE = map { lc($_) => 1 } split ' ', '#BEDEFF #FFF2A7 #FFA500 #930031 #2b1a20 #6b5a5f #fffdf6 #e6dccb #f3ecdc #efe6d6 #ffffff';
sub html_text {
  my $h = shift;
  $h =~ s/<(style|script)\b.*?<\/\1>//gs;
  $h =~ s/<!--.*?-->//gs;
  $h =~ s/<[^>]+>/ /g;
  $h =~ s/&lt;/</g; $h =~ s/&gt;/>/g; $h =~ s/&quot;/"/g; $h =~ s/&amp;/&/g;
  $h =~ s/\s+/ /g;
  return $h;
}
sub gate_D {
  my $hf = shift // $HTML_DEFAULT;
  unless (-e $hf) { err('D', "找不到 HTML：$hf"); return 0; }
  my $html = read_utf8($hf);
  # 色票
  my %bad;
  while ($html =~ /(#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b)/g) { $bad{$1}++ unless $PALETTE{lc $1}; }
  err('D', "使用色票以外的顏色：".join('、', sort keys %bad)) if %bad;
  err('D', '使用 rgb()/rgba()/hsl() 顏色，請改用色票變數') if $html =~ /\b(rgba?|hsla?)\(/;
  # 外部資源
  err('D', '含外部資源連結（需可離線開啟）') if $html =~ /<(script|link)[^>]+(src|href)=["']https?:/;
  my %SEC;
  while ($html =~ /<section class="slide[^"]*" data-id="(S\d\d)"[^>]*>(.*?)<\/section>/gs) { $SEC{$1} = $2; }
  my @S = parse_slides("$DD/spec.md");
  # 頁首會顯示大綱的「章節」（例如「第1課」），其中的數字視為規格內容
  my %CHAP = map { $_->{id} => ($_->{f}{章節}[0] // '') } parse_slides("$DD/outline.md");
  my $i = 0;
  for my $s (@S) {
    $i++;
    my $id = $s->{id};
    my $sec = $SEC{$id};
    if (!defined $sec) { err('D', "$id 在 HTML 中不存在"); next; }
    my $t = html_text($sec);
    my $nt = norm_text($t);
    # 頁碼與來源
    my $pg = sprintf('%02d', $i);
    err('D', "$id 頁碼不是 $pg") unless $sec =~ /class="pg">\Q$pg\E</;
    err('D', "$id 沒有資料來源頁尾") unless $sec =~ /class="folio"><span>資料來源：\S/;
    # 主張與條列原文
    my $claim = $s->{f}{主張}[0] // '';
    err('D', "$id 畫面上找不到主張原文") if index($nt, norm_text($claim)) < 0;
    my @b = Spec::bullets(@{$s->{sec}{條列} // []});
    for my $b (@b) { err('D', "$id 畫面上找不到條列：$b") if index($nt, norm_text($b)) < 0; }
    # 圖表值
    my @rows = table_rows(@{$s->{sec}{圖表資料} // []});
    my %tn = map { $_ => 1 } numbers_in($t);
    my %symc; $symc{$_->[1]}++ for grep { $SYM{$_->[1]} } @rows;
    for my $r (@rows) {
      my $v = $r->[1];
      next if $SYM{$v};
      if (defined numval($v) && $v !~ /^\d{4}-\d\d-\d\d$/) { err('D', "$id 圖表數值 $v（$r->[0]）未出現在畫面") unless $tn{norm_num($v =~ s/%$//r)}; }
      else { err('D', "$id 圖表文字「$v」（$r->[0]）未出現在畫面") if index($nt, norm_text($v)) < 0; }
    }
    my %cls = ('●' => 'dot', '○' => 'ring', '△' => 'tri', '—' => 'dash');
    for my $k (keys %symc) {
      my $c = () = $sec =~ /<td><i class="$cls{$k}"/g;
      err('D', "$id 矩陣符號 $k 應有 $symc{$k} 個，畫面上 $c 個") if $c != $symc{$k};
    }
    # 畫面上的數字都必須來自本頁規格
    my $spec_txt = join(' ', $s->{title}, $CHAP{$id} // '', $id, $pg, $claim, @b, @{$s->{f}{圖說} // []}, Spec::bullets(@{$s->{sec}{來源} // []}), map { @$_ } @rows);
    my %sn = map { $_ => 1 } numbers_in($spec_txt);
    for my $n (numbers_in($t)) {
      next if $sn{$n} || $n =~ /^(19|20)\d\d$/;
      err('D', "$id 畫面出現規格沒有的數字：$n");
    }
    # 評價詞
    (my $x = $t) =~ s/「[^」]*」//g;
    for my $w (@BANNED) { err('D', "$id 畫面含評價性字詞「$w」") if index($x, $w) >= 0; }
  }
  for my $k (sort keys %SEC) { err('D', "HTML 多出規格沒有的頁面 $k") unless grep { $_->{id} eq $k } @S; }
  printf "D: %d 頁（靜態檢查）；版面溢出請另以瀏覽器執行 check_layout.js\n", scalar(keys %SEC);
  return 0;
}

# ---------- 執行 ----------
my $rc = 0;
print "facts: ".scalar(@FACTS)." 張\n";
gate_A() if $gate eq 'A' || $gate eq 'ALL';
gate_B() if $gate eq 'B' || $gate eq 'ALL';
gate_C() if $gate eq 'C' || $gate eq 'ALL';
gate_D() if $gate eq "D" || $gate eq "ALL";
print "\n";
print "ERROR $_\n" for @ERR;
print "WARN  $_\n" for @WARN;
printf "\n結果：%s（ERROR %d、WARN %d）\n", (@ERR ? '不通過' : '通過'), scalar(@ERR), scalar(@WARN);
exit(@ERR ? 1 : $rc);
