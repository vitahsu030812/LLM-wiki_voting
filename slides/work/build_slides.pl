#!/usr/bin/perl
# 第 3 步：依 spec.md 產生投影片 HTML（不新增任何內容，只負責排版）
# 用法：perl build_slides.pl [輸出路徑，預設 ../2026員林市選舉-選民參考簡報.html]
use strict; use warnings; use utf8;
our $NOHI = 0;
use FindBin; use lib $FindBin::Bin;
use Spec qw(parse_slides table_rows bullets);
binmode STDOUT, ':encoding(UTF-8)';

my $DIR = $FindBin::Bin;
# 簡報種類：voter＝選民參考簡報（預設）；lesson＝選前小教學（檔案在 lesson/）
my $DECK = lc($ENV{DECK} // 'voter');
die "DECK 只能是 voter 或 lesson\n" unless $DECK =~ /^(voter|lesson)$/;
my $DD  = $DECK eq 'lesson' ? "$DIR/lesson" : $DIR;
my $OUT = shift // ($DECK eq 'lesson' ? "$DIR/../2026員林市選舉-選前小教學.html" : "$DIR/../2026員林市選舉-選民參考簡報.html");
my %BRAND = $DECK eq 'lesson'
  ? (mast => '員林選前小教學', big => '選前<br>小教學', title => '2026 員林選前小教學', toc => '課程內容')
  : (mast => '員林選舉特刊',   big => '選前<br>必讀',   title => '2026 員林選民手冊',   toc => '本期內容');
my %O = map { $_->{id} => $_ } parse_slides("$DD/outline.md");
my @S = parse_slides("$DD/spec.md");

# 顯示用：標記對照（定義於 spec.md「標記顯示對照」）
my %TAGSHOW = ('現任' => '現任', '當選' => '現任', '再戰' => '再戰', '落選' => '曾參選', '新人參選' => '新人', '提名參選' => '政黨提名', '參選人' => '', '接棒' => '', '提名' => '');
my %TAGCLS  = ('現任' => 'inc', '再戰' => 're', '曾參選' => 're', '新人' => 'new', '政黨提名' => 'up');
my @RACES = qw(縣長 市長 縣議員 市民代表 里長);

sub h { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s; }
sub isnum { my $v = shift // ''; (my $x = $v) =~ s/[,%]//g; return $x =~ /^-?\d+(\.\d+)?$/; }
sub nval  { my $v = shift // 0; $v =~ s/[,%]//g; return $v + 0; }
sub fmt   { my $v = shift // ''; return $v if $v =~ /%$/ || $v !~ /^\d+$/; 1 while $v =~ s/^(\d+)(\d{3})/$1,$2/; return $v; }
sub parts { return split /｜/, shift; }
sub last_part { my @p = parts(shift); return $p[-1]; }
sub tagshow { my $t = shift // ''; return exists $TAGSHOW{$t} ? $TAGSHOW{$t} : $t; }

# ---------------- 圖表 renderers ----------------
sub r_hbar {
  my @r = grep { isnum($_->[1]) } @_;
  my $max = 0; $max < nval($_->[1]) and $max = nval($_->[1]) for @r;
  my $html = '<div class="hb">';
  for my $x (@r) {
    my $cls = $main::NOHI ? '' : ($x->[3] // '') eq '當選' ? 'hi' : (($x->[3] // '') eq '落選' ? '' : (@r <= 12 && nval($x->[1]) == $max ? 'hi' : ''));
    $html .= sprintf('<div class="r %s"><span class="l">%s</span><span class="tr"><span class="f" style="width:%.1f%%"></span></span><span class="v">%s</span></div>',
      $cls, h(last_part($x->[0])), nval($x->[1]) / ($max || 1) * 100, h(fmt($x->[1])));
  }
  return $html.'</div>';
}

sub r_column {
  my @r = grep { isnum($_->[1]) && $_->[0] ne '合計' } @_;
  my ($tot) = grep { $_->[0] eq '合計' } @_;
  my $max = 0; $max < nval($_->[1]) and $max = nval($_->[1]) for @r;
  my $html = $tot ? '<div class="stat"><span class="kicknum">'.h(fmt($tot->[1])).'</span><span class="lab">'.h($tot->[0]).'</span></div>' : '';
  $html .= '<div class="vc">';
  for my $x (@r) {
    my $hi = nval($x->[1]) == $max ? ' hi' : '';
    $html .= sprintf('<div class="col"><span class="num">%s</span><div class="bar%s" style="height:%.1f%%"></div><span class="cl">%s</span></div>', h(fmt($x->[1])), $hi, nval($x->[1]) / ($max || 1) * 78, h($x->[0]));
  }
  return $html.'</div>';
}

sub r_grouped {
  my (@g, %g, @ser, %ser);
  for my $x (@_) { my ($a, $b) = parts($x->[0]); push @g, $a unless $g{$a}++; push @ser, $b unless $ser{$b}++; }
  my %v = map { $_->[0] => $_->[1] } @_;
  my $max = 0; $max < nval($_->[1]) and $max = nval($_->[1]) for @_;
  my @col = ('var(--wine)', 'var(--sky)', 'var(--orange)');
  my $html = '<div class="legend">'.join('', map { "<span><i style=\"background:$col[$_]\"></i>".h($ser[$_]).'</span>' } 0..$#ser).'</div><div class="gc">';
  for my $a (@g) {
    $html .= '<div class="g"><div class="gb">';
    for my $i (0..$#ser) {
      my $val = $v{"$a｜$ser[$i]"} // next;
      $html .= sprintf('<div class="b" style="height:%.1f%%;background:%s"><span>%s</span></div>', nval($val) / ($max || 1) * 80, $col[$i], h($val));
    }
    $html .= '</div><div class="gl">'.h($a).'</div></div>';
  }
  return $html.'</div>';
}

sub r_donut {
  my (@names, %d, @other);
  for my $x (@_) {
    my @p = parts($x->[0]);
    if (@p == 2) { push @names, $p[0] unless exists $d{$p[0]}; $d{$p[0]}{$p[1]} = $x->[1]; } else { push @other, $x; }
  }
  my @col = ('var(--wine)', 'var(--orange)', 'var(--sky)');
  my ($acc, @seg) = (0);
  for my $i (0..$#names) { my $r = nval($d{$names[$i]}{'得票率'}); push @seg, sprintf('%s %.2f%% %.2f%%', $col[$i % 3], $acc, $acc + $r); $acc += $r; }
  my $center = @other ? '<div class="c"><b>'.h(fmt($other[0][1])).'</b><span>'.h($other[0][0]).'</span></div>' : '';
  my $html = '<div class="donutrow"><div class="donut" style="background:conic-gradient('.join(',', @seg).')">'.$center.'</div><div class="dleg">';
  for my $i (0..$#names) {
    my $n = $names[$i];
    $html .= '<div class="dl"><i style="background:'.$col[$i % 3].'"></i><b>'.h($n).'</b><span>'.h(fmt($d{$n}{'票數'} // '')).' 票</span><span class="pc">'.h($d{$n}{'得票率'} // '').'</span></div>';
  }
  return $html.'</div></div>';
}

sub r_stacked {
  my (@names, %d);
  for my $x (@_) { my ($n, $k) = parts($x->[0]); push @names, $n unless exists $d{$n}; $d{$n}{$k} = $x->[1]; }
  my @col = ('var(--wine)', 'var(--orange)', 'var(--sky)');
  my $html = '<div class="stk">';
  for my $i (0..$#names) {
    my $r = $d{$names[$i]}{'得票率'};
    my $lab = nval($r) >= 10 ? h($names[$i]).' '.h($r) : '';
    $html .= sprintf('<div style="width:%s;background:%s" class="%s">%s</div>', h($r), $col[$i % 3], ($i == 0 ? 'dk' : ''), $lab);
  }
  $html .= '</div><div class="hb" style="margin-top:22px">';
  my $max = 0; $max < nval($d{$_}{'票數'}) and $max = nval($d{$_}{'票數'}) for @names;
  for my $i (0..$#names) {
    my $n = $names[$i];
    $html .= sprintf('<div class="r %s"><span class="l">%s</span><span class="tr tall"><span class="f" style="width:%.1f%%;background:%s"></span></span><span class="v">%s 票｜%s</span></div>',
      ($i == 0 ? 'hi' : ''), h($n), nval($d{$n}{'票數'}) / ($max || 1) * 100, $col[$i % 3], h(fmt($d{$n}{'票數'})), h($d{$n}{'得票率'}));
  }
  return $html.'</div>';
}

sub sym {
  my $v = shift;
  return '<i class="dot" title="有提出主張"></i>' if $v eq '●';
  return '<i class="ring" title="已提出但內容待查"></i>' if $v eq '○';
  return '<i class="tri" title="表態保留"></i>' if $v eq '△';
  return '<i class="dash" title="公開報導中未見"></i>';
}
sub r_matrix {
  my (@rowk, %rk, @colk, %ck, %cell, @num);
  for my $x (@_) {
    if (isnum($x->[1])) { push @num, $x; next; }
    my @p = parts($x->[0]); my ($r, $c) = @p[-2, -1];
    push @rowk, $r unless $rk{$r}++; push @colk, $c unless $ck{$c}++; $cell{"$r\t$c"} = $x->[1];
  }
  my $html = '<div class="legend"><span><i class="dot"></i>有提出主張</span><span><i class="ring"></i>內容待查</span><span><i class="tri"></i>表態保留</span><span><i class="dash"></i>報導中未見</span></div>';
  $html .= '<table class="mx"><tr><th></th>'.join('', map { '<th>'.h($_).'</th>' } @colk).'</tr>';
  for my $r (@rowk) { $html .= '<tr><td>'.h($r).'</td>'.join('', map { '<td>'.sym($cell{"$r\t$_"} // '—').'</td>' } @colk).'</tr>'; }
  $html .= '</table>';
  $html .= '<div class="sub">'.r_hbar(@num).'</div>' if @num;
  return $html;
}

sub r_timeline {
  my (@cand, %ck, %cell, %per);
  my @order = ('更早', '經歷', '2018', '2022', '2026');
  for my $x (@_) { my ($c, $p) = parts($x->[0]); push @cand, $c unless $ck{$c}++; $cell{"$c\t$p"} = $x->[1]; $per{$p} = 1; }
  my @cols = grep { $per{$_} } @order;
  my $html = '<div class="tl" style="grid-template-columns:96px repeat('.scalar(@cols).',1fr)"><div class="yr hd">候選人</div>'.join('', map { '<div class="yr">'.h($_).'</div>' } @cols);
  for my $c (@cand) {
    $html .= '<div class="nm">'.h($c).'</div>';
    for my $p (@cols) {
      my $v = $cell{"$c\t$p"};
      if (!defined $v) { $html .= '<div><span class="chip none">—</span></div>'; next; }
      if ($v eq $c)    { $html .= '<div><span class="chip now">登記參選</span></div>'; next; }
      my $t = isnum($v) ? fmt($v).' 票' : $v;
      $html .= '<div><span class="chip '.($v eq '待查' ? 'none' : 'w').'">'.h($t).'</span></div>';
    }
  }
  return $html.'</div>';
}

sub r_units {
  my (@g, %g);
  for my $x (@_) { my ($a) = parts($x->[0]); push @g, $a unless $g{$a}++; push @{$g{"L\t$a"}}, $x; }
  my @bg = ('var(--wine)', 'var(--sky)', 'var(--orange)', 'var(--butter)');
  my $html = '<div class="units" style="grid-template-columns:repeat('.scalar(@g).',1fr)">';
  for my $i (0..$#g) {
    my $a = $g[$i]; my @m = @{$g{"L\t$a"}};
    $html .= '<div class="ugrp"><h4>'.h($a).' <b>'.scalar(@m).'</b></h4>';
    for my $x (@m) { my (undef, $no) = parts($x->[0]); $html .= '<div class="u'.($i == 0 ? ' dk' : '').'" style="background:'.$bg[$i % 4].'"><span>'.h($x->[1]).'</span><span class="nb">'.h($no).' 號</span></div>'; }
    $html .= '</div>';
  }
  return $html.'</div>';
}

sub r_directory {
  my (@g, %g);
  for my $x (@_) { my ($a) = parts($x->[0]); push @g, $a unless $g{$a}++; push @{$g{"L\t$a"}}, $x; }
  my $html = '<div class="dir">';
  for my $a (@g) {
    my @m = @{$g{"L\t$a"}};
    $html .= '<div><h3>'.h($a).' <small>'.scalar(@m).' 人</small></h3><ol>';
    for my $x (@m) {
      my (undef, $no) = parts($x->[0]); my $t = tagshow($x->[3]);
      $html .= '<li><span class="n">'.h($no).'</span><b>'.h($x->[1]).'</b><span>'.($t ne '' ? '<span class="tg '.($TAGCLS{$t} // 'new').'">'.h($t).'</span>' : '').'</span></li>';
    }
    $html .= '</ol></div>';
  }
  return $html.'</div>';
}

sub r_lichart {
  my (@li, %d);
  for my $x (@_) {
    my ($l, $k) = parts($x->[0]); push @li, $l unless $d{$l};
    $d{$l} //= { c => [] };
    if ($k =~ /得票率/) { $d{$l}{rate} = $x->[1]; } elsif ($k =~ /當選人/) { $d{$l}{win} = $x->[1]; } else { push @{$d{$l}{c}}, [$k, $x->[1]]; }
  }
  my $html = '<div class="legend"><span><i style="background:var(--sky)"></i>2022 當選者續選</span><span><i style="background:var(--orange)"></i>2022 當選者未登記</span><span><i class="hatch"></i>2022 同額競選</span></div><div class="lic"><div class="r hd"><span>里</span><span>2022 當選者得票率</span><span>2026 候選人（號次）</span></div>';
  for my $l (@li) {
    my $x = $d{$l};
    my $runs = grep { $_->[1] eq ($x->{win} // '') } @{$x->{c}};
    my $cls = nval($x->{rate}) >= 100 ? 'unc' : ($runs ? '' : 'out');
    $html .= sprintf('<div class="r"><span class="l">%s</span><span class="tr"><span class="f %s" style="width:%s"></span><span class="p">%s %s</span></span><span class="cand">%s</span></div>',
      h($l), $cls, h($x->{rate}), h($x->{win}), h($x->{rate}), join(' · ', map { h("$_->[0] $_->[1]") } @{$x->{c}}));
  }
  return $html.'</div>';
}

sub svg_text { my ($x, $y, $t, $cls, $anchor) = @_; return sprintf('<text x="%d" y="%d" class="%s" text-anchor="%s">%s</text>', $x, $y, $cls, $anchor // 'start', h($t)); }

sub r_network {
  my @r = @_;
  if (isnum($r[0][1])) {   # 議題 × 選舉層級（二分圖）
    my (@t, %t, %rc);
    for my $x (@r) { my ($a, $b) = parts($x->[0]); push @t, $a unless $t{$a}++; $rc{$b} = 1; }
    my @rs = grep { $rc{$_} } @RACES;
    my ($W, $H) = (640, 430);
    my %ty = map { $t[$_] => 40 + $_ * (($H - 80) / (@t - 1 || 1)) } 0..$#t;
    my %ry = map { $rs[$_] => 30 + $_ * (($H - 60) / (@rs - 1 || 1)) } 0..$#rs;
    my @tc = ('wine', 'orange', 'sky');           # 每個議題一個顏色
    my %tci = map { $t[$_] => $tc[$_ % 3] } 0..$#t;
    my $svg = qq{<svg viewBox="0 0 $W $H" class="net" role="img" aria-label="議題與選舉層級關係圖">};
    my %chips;
    for my $x (@r) {
      my ($a, $b) = parts($x->[0]); my ($y1, $y2) = ($ty{$a}, $ry{$b}); my $w = 2 + nval($x->[1]) * 1.4;
      $svg .= sprintf('<path d="M230 %d C330 %d 340 %d 430 %d" class="edge e-%s" style="stroke-width:%.1f"/>', $y1, $y1, $y2, $y2, $tci{$a}, $w);
      push @{$chips{$b}}, [$tci{$a}, $x->[1]];
    }
    for my $a (@t) { $svg .= sprintf('<rect x="0" y="%d" width="230" height="40" class="t-%s"/>', $ty{$a} - 20, $tci{$a}).svg_text(115, $ty{$a} + 6, $a, "tt-$tci{$a}", 'middle'); }
    for my $b (@rs) {
      $svg .= sprintf('<rect x="430" y="%d" width="210" height="44" class="box"/>', $ry{$b} - 22).svg_text(442, $ry{$b} + 6, $b, 'n2t');
      my $cx = 520;
      for my $c (@{$chips{$b} // []}) {
        $svg .= sprintf('<rect x="%d" y="%d" width="34" height="26" class="t-%s"/>', $cx, $ry{$b} - 13, $c->[0]).svg_text($cx + 17, $ry{$b} + 6, $c->[1], "tt-$c->[0]", 'middle');
        $cx += 38;
      }
    }
    return $svg.'</svg>';
  }
  # 議題 → 地區 → 候選人（放射狀）
  my (@g, %g);
  for my $x (@r) { my ($a, $n) = parts($x->[0]); push @g, $a unless $g{$a}++; push @{$g{"L\t$a"}}, [$n, $x->[1]]; }
  # 依高度把各組交替堆疊到左右兩欄
  my @pos; my @colh = (4, 4);
  for my $i (0..$#g) {
    my $bh = 30 + 40 * @{$g{"L\t$g[$i]"}};
    my $c = $colh[0] <= $colh[1] ? 0 : 1;
    push @pos, [$c ? 420 : 0, $colh[$c]]; $colh[$c] += $bh + 14;
  }
  my $W = 640; my $H = ($colh[0] > $colh[1] ? $colh[0] : $colh[1]);
  my ($cx, $cy) = (320, int($H / 2));
  my $svg = qq{<svg viewBox="0 0 $W $H" class="net" role="img" aria-label="議題與候選人關係圖">};
  my $body = '';
  for my $i (0..$#g) {
    my $a = $g[$i]; my @m = @{$g{"L\t$a"}}; my ($x, $y) = @{$pos[$i]}; my $bh = 30 + 40 * @m;
    my $ex = $x == 0 ? 220 : 420; my $ey = $y + $bh / 2;
    $svg .= sprintf('<path d="M%d %d L%d %d" class="edge" style="stroke-width:%.1f"/>', $cx + ($x == 0 ? -80 : 80), $cy, $ex, $ey, 2 + @m * 1.5);
    $body .= sprintf('<rect x="%d" y="%d" width="220" height="%d" class="box"/><rect x="%d" y="%d" width="220" height="24" class="n1"/>', $x, $y, $bh, $x, $y);
    $body .= svg_text($x + 10, $y + 17, $a.'（'.scalar(@m).'）', 'n1t');
    for my $j (0..$#m) {
      $body .= svg_text($x + 10, $y + 44 + 40 * $j, $m[$j][0], 'bn');
      $body .= svg_text($x + 10, $y + 63 + 40 * $j, $m[$j][1], 'bs');
    }
  }
  my ($topic) = map { (my $t = $_) =~ s/^.*?：//; $t } ($r[0][2] // '');
  $svg .= $body.sprintf('<rect x="%d" y="%d" width="160" height="60" class="hub"/>', $cx - 80, $cy - 30);
  return $svg.svg_text($cx, $cy + 7, '__TOPIC__', 'hubt', 'middle').'</svg>';
}

sub r_flow {
  my (%from, %to, @links);
  for my $x (@_) {
    my ($to26, $nm, $dir) = parts($x->[0]); my ($f, $t) = split /→/, $dir;
    push @{$from{$f}}, $nm; push @{$to{$t}}, $nm; push @links, [$nm, $f, $t, $x->[1]];
  }
  my @L = grep { $from{$_} } @RACES; my @R = grep { $to{$_} } @RACES;
  my ($W) = 640;
  my (%ly, %ry, $y);
  my $svg_nodes = '';
  my $place = sub {
    my ($list, $map, $x, $hd) = @_; my $yy = 34;
    $svg_nodes .= svg_text($x + 100, 18, $hd, 'colh', 'middle');
    for my $k (@$list) {
      my @n = @{$map->{$k}}; my $hgt = 30 + 22 * @n;
      $svg_nodes .= sprintf('<rect x="%d" y="%d" width="200" height="%d" class="box"/><rect x="%d" y="%d" width="200" height="24" class="n1"/>', $x, $yy, $hgt, $x, $yy).svg_text($x + 10, $yy + 17, $k, 'n1t');
      for my $j (0..$#n) { $svg_nodes .= svg_text($x + 12, $yy + 44 + 22 * $j, $n[$j], 'bn'); ($x == 0 ? \%ly : \%ry)->{$n[$j]} = $yy + 39 + 22 * $j; }
      $yy += $hgt + 14;
    }
    return $yy;
  };
  my $h1 = $place->(\@L, \%from, 0, '2022 參選');
  my $h2 = $place->(\@R, \%to, 440, '2026 參選');
  my $H = ($h1 > $h2 ? $h1 : $h2) + 4;
  my $svg = qq{<svg viewBox="0 0 $W $H" class="net" role="img" aria-label="2022 與 2026 參選層級變化">};
  for my $l (@links) { my ($a, $b) = ($ly{$l->[0]}, $ry{$l->[0]}); $svg .= sprintf('<path d="M200 %d C320 %d 320 %d 440 %d" class="edge thin"><title>%s</title></path>', $a, $a, $b, $b, h("$l->[0]：$l->[3]")); }
  return $svg.$svg_nodes.'</svg>';
}

sub r_checklist {
  my @bg = ('var(--sky)', 'var(--butter)', 'var(--orange)');
  my $i = 0;
  return '<div class="ck" style="grid-template-rows:repeat('.scalar(@_).',1fr)">'.join('', map { my ($q, $d) = split /？/, $_->[1], 2; '<div style="background:'.$bg[$i++ % 3].'"><span class="kicknum">'.h($_->[0]).'</span><div><b>'.h("$q？").'</b><small>'.h($d // '').'</small></div></div>' } @_).'</div>';
}

sub r_cover {
  my ($date) = grep { $_->[0] eq '投票日' } @_;
  my @o = grep { $_->[0] ne '投票日' } @_;
  return { date => $date ? $date->[1] : '', lines => join('', map { '<div class="ln"><i>'.h($_->[1]).'</i>'.h($_->[0]).'</div>' } @o) };
}

# 教學用：學習目標（標籤＝小標，值＝目標文字）
sub r_goals {
  # 序號用 CSS counter 畫出（不寫進 HTML 文字，避免畫面出現規格以外的數字）
  return '<ol class="goals'.(@_ >= 6 ? ' dense' : '').'">'.join('', map { '<li><span class="kicknum"></span><div><small>'.h($_->[0]).'</small><b>'.h($_->[1]).'</b></div></li>' } @_).'</ol>';
}

# 教學用：小測驗（標籤：問／A–D 選項／答／解）。答案用 <details> 收合，不需 JavaScript
sub r_quiz {
  my ($q)  = grep { $_->[0] eq '問' } @_;
  my @op   = grep { $_->[0] =~ /^[A-D]$/ } @_;
  my ($a)  = grep { $_->[0] eq '答' } @_;
  my @ex   = grep { $_->[0] eq '解' } @_;
  my $html = '<div class="qz"><span class="qtag">小測驗</span><p class="q">'.h($q ? $q->[1] : '').'</p>';
  $html .= '<ol class="opts">'.join('', map { '<li><b>'.h($_->[0]).'</b><span>'.h($_->[1]).'</span></li>' } @op).'</ol>' if @op;
  $html .= '<details class="ans"><summary>看答案</summary><p><b>答案：</b>'.h($a ? $a->[1] : '').'</p>'.join('', map { '<p>'.h($_->[1]).'</p>' } @ex).'</details>';
  return $html.'</div>';
}

my %R = (goals => \&r_goals, cards => \&r_goals, quiz => \&r_quiz, hbar => \&r_hbar, column => \&r_column, grouped => \&r_grouped, donut => \&r_donut, stacked => \&r_stacked, matrix => \&r_matrix,
  timeline => \&r_timeline, units => \&r_units, directory => \&r_directory, 'li-chart' => \&r_lichart, network => \&r_network, flow => \&r_flow,
  checklist => \&r_checklist, colophon => sub { local $main::NOHI = 1; r_hbar(@_) });   # 政黨分布不做強調色，避免凸顯特定政黨

# ---------------- 組頁 ----------------
my @sec;
my $n = 0;
for my $s (@S) {
  $n++;
  my $o = $O{$s->{id}} // { f => {} };
  my $chap = $o->{f}{章節}[0] // '';
  my $claim = $s->{f}{主張}[0] // '';
  my $type = $s->{f}{圖型}[0] // '';
  (my $title = $s->{title}) =~ s/^\s+//;
  my @rows = table_rows(@{$s->{sec}{圖表資料} // []});
  my @b = bullets(@{$s->{sec}{條列} // []});
  my @src = bullets(@{$s->{sec}{來源} // []});
  my $cap = $s->{f}{圖說}[0];
  my $pg = sprintf('%02d', $n);
  my $folio = '<div class="folio"><span>資料來源：'.h(join('；', @src)).'</span><span class="pg">'.$pg.'</span></div>';
  if ($type eq 'cover') {
    my $c = r_cover(@rows);
    push @sec, qq{<section class="slide cover" data-id="$s->{id}" data-title="}.h($title).qq{">
  <div class="mast"><b>$BRAND{mast}</b><span>}.h($chap).qq{</span><span>$s->{id}</span></div>
  <div class="bigt">$BRAND{big}<span>2026 員林市地方選舉</span></div>
  <div class="ribbon">投票日 }.h($c->{date}).qq{</div>
  <p class="claim">}.h($claim).qq{</p>
  <div class="lines"><h5>$BRAND{toc}</h5>$c->{lines}</div>
  <ul class="fine">}.join('', map { '<li>'.h($_).'</li>' } @b).qq{</ul>
  $folio
</section>};
    next;
  }
  my $chart = $R{$type} ? $R{$type}->(@rows) : '<p>（未支援的圖型 '.h($type).'）</p>';
  if ($type eq 'network') { (my $t = $title) =~ s/^.*?：//; $chart =~ s/__TOPIC__/h($t)/e; }
  push @sec, qq{<section class="slide" data-id="$s->{id}" data-title="}.h($title).qq{">
  <div class="mast"><b>}.h($chap).qq{</b><span>$BRAND{mast}</span><span>$s->{id}</span></div>
  <span class="sec">}.h($title).qq{</span>
  <h2>}.h($claim).qq{</h2>
  <div class="spread">
    <div class="fig">$chart}.(defined $cap ? '<div class="figcap">'.h($cap).'</div>' : '').qq{</div>
    <div class="txt"><ul class="pts">}.join('', map { '<li>'.h($_).'</li>' } @b).qq{</ul></div>
  </div>
  $folio
</section>};
}

local $/; my $tpl = <DATA>;
$tpl =~ s/__SLIDES__/join("\n", @sec)/e;
$tpl =~ s/__TITLE__/$BRAND{title}/;
open my $fh, '>:encoding(UTF-8)', $OUT or die "cannot write $OUT: $!";
print $fh $tpl; close $fh;
print "slides: ".scalar(@sec)." → $OUT\n";

__DATA__
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<!-- 由 slides/work/build_slides.pl 依 spec.md 自動產生，請勿手改 -->
<style>
:root{
  --sky:#BEDEFF; --butter:#FFF2A7; --orange:#FFA500; --wine:#930031;
  --ink:#2b1a20; --ink2:#6b5a5f; --paper:#fffdf6; --hair:#e6dccb; --track:#f3ecdc; --bg:#efe6d6; --white:#ffffff;
  --serif:"Noto Serif TC","Songti TC","PMingLiU","MingLiU",serif;
  --sans:"Noto Sans TC","PingFang TC","Microsoft JhengHei",system-ui,sans-serif;
}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{background:var(--bg);color:var(--ink);font-family:var(--sans);overflow:hidden}
#stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
#deck{width:1280px;height:720px;position:relative;transform-origin:center center}
.slide{position:absolute;inset:0;background:var(--paper);border:1px solid var(--hair);padding:28px 56px 44px;display:none;flex-direction:column;overflow:hidden}
.slide.active{display:flex}
.mast{display:flex;justify-content:space-between;align-items:baseline;font-size:12px;letter-spacing:.18em;color:var(--ink2);border-bottom:2px solid var(--ink);padding-bottom:6px;margin-bottom:12px}
.mast b{color:var(--wine);letter-spacing:.24em}
.folio{position:absolute;bottom:12px;left:56px;right:56px;display:flex;justify-content:space-between;gap:20px;font-size:11.5px;color:var(--ink2);border-top:1px solid var(--hair);padding-top:6px}
.folio .pg{font-family:var(--serif);font-weight:700;color:var(--wine);font-size:14px}
.sec{align-self:flex-start;background:var(--wine);color:var(--white);font-size:12.5px;font-weight:700;letter-spacing:.12em;padding:3px 10px;margin-bottom:6px}
h2{font-family:var(--serif);font-size:34px;line-height:1.2;margin:0 0 14px;font-weight:900}
.spread{flex:1;min-height:0;display:grid;grid-template-columns:6fr 4fr}
.fig{border-right:1px solid var(--ink);padding:0 24px 0 0;display:flex;flex-direction:column;min-height:0;min-width:0}
.txt{padding:0 0 0 24px;display:flex;flex-direction:column;min-height:0;min-width:0}
.figcap{font-size:12px;color:var(--ink2);margin-top:8px;font-family:var(--serif)}
ul.pts{list-style:none;margin:0;padding:0}
ul.pts>li{position:relative;padding:7px 0 7px 22px;border-bottom:1px solid var(--hair);font-size:15.5px;line-height:1.5}
ul.pts>li:before{content:"";position:absolute;left:2px;top:15px;width:9px;height:9px;background:var(--orange)}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12.5px;color:var(--ink2);margin-bottom:10px;align-items:center}
.legend i{display:inline-block;width:12px;height:12px;margin-right:5px;vertical-align:-1px}
.kicknum{font-family:var(--serif);font-size:54px;font-weight:900;color:var(--wine);line-height:1}
.stat{display:flex;align-items:baseline;gap:10px;border-bottom:2px solid var(--ink);padding-bottom:6px;margin-bottom:10px}
.stat .lab{font-size:14px;color:var(--ink2)}
/* hbar */
.hb{display:flex;flex-direction:column;gap:5px}
.hb .r{display:grid;grid-template-columns:110px 1fr 140px;align-items:center;gap:10px;font-size:14px}
.hb .tr{height:18px;background:var(--track);position:relative}
.hb .tr.tall{height:30px}
.hb .f{position:absolute;left:0;top:0;bottom:0;background:var(--sky)}
.hb .r.hi .f{background:var(--wine)}
.hb .r.hi .l{font-weight:800;color:var(--wine)}
.hb .v{font-variant-numeric:tabular-nums;color:var(--ink2);font-size:13px;white-space:nowrap}
.sub{margin-top:16px;border-top:1px solid var(--hair);padding-top:10px}
/* column */
.vc{flex:1;display:flex;align-items:flex-end;gap:20px;border-bottom:2px solid var(--ink);padding:0 8px;min-height:0;margin-bottom:30px}
.gc{margin-bottom:30px}
.vc .col{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;position:relative;padding-bottom:26px}
.vc .bar{width:100%;background:var(--sky)} .vc .bar.hi{background:var(--wine)}
.vc .num{font-family:var(--serif);font-size:28px;font-weight:900;margin-bottom:4px}
.vc .cl{position:absolute;bottom:-24px;font-size:14px;font-weight:700;white-space:nowrap}
/* grouped */
.gc{flex:1;display:flex;gap:26px;border-bottom:2px solid var(--ink);padding:0 10px;min-height:0}
.gc .g{flex:1;display:flex;flex-direction:column;justify-content:flex-end;position:relative;padding-bottom:26px}
.gc .gb{flex:1;display:flex;align-items:flex-end;gap:5px}
.gc .b{flex:1;position:relative;display:flex;justify-content:center}
.gc .b span{position:absolute;top:-22px;font-family:var(--serif);font-weight:900;font-size:17px}
.gc .gl{position:absolute;bottom:-24px;left:0;right:0;text-align:center;font-size:14px;font-weight:700}
/* donut */
.donutrow{display:flex;align-items:center;gap:28px;flex:1}
.donut{width:260px;height:260px;border-radius:50%;position:relative;flex:none}
.donut:after{content:"";position:absolute;inset:60px;border-radius:50%;background:var(--paper)}
.donut .c{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;z-index:1;font-family:var(--serif)}
.donut .c b{font-size:30px;color:var(--wine)} .donut .c span{font-size:13px;color:var(--ink2)}
.dleg{flex:1;display:flex;flex-direction:column;gap:10px}
.dl{display:grid;grid-template-columns:16px 70px 1fr 70px;align-items:center;gap:8px;font-size:15px;border-bottom:1px solid var(--hair);padding-bottom:6px}
.dl i{width:14px;height:14px;display:inline-block} .dl .pc{font-family:var(--serif);font-weight:900;color:var(--wine)}
/* stacked */
.stk{display:flex;height:56px;border:2px solid var(--ink);margin-top:10px}
.stk div{display:flex;align-items:center;padding-left:10px;font-weight:700;white-space:nowrap;overflow:hidden}
.stk .dk{color:var(--white)}
/* matrix */
table.mx{border-collapse:collapse;width:100%;font-size:14px}
table.mx th{font-size:12.5px;color:var(--ink2);padding:6px 4px;border-bottom:2px solid var(--ink);text-align:center}
table.mx td{border-bottom:1px solid var(--hair);padding:9px 4px;text-align:center}
table.mx td:first-child{text-align:left;font-family:var(--serif);font-size:18px;font-weight:900}
.dot,.ring,.tri,.dash{display:inline-block}
.dot{width:18px;height:18px;border-radius:50%;background:var(--wine)}
.ring{width:18px;height:18px;border-radius:50%;border:3px solid var(--wine)}
.tri{width:0;height:0;border-left:10px solid transparent;border-right:10px solid transparent;border-bottom:17px solid var(--orange)}
.dash{width:16px;height:3px;background:var(--hair);vertical-align:middle}
.legend .dot,.legend .ring{width:12px;height:12px} .legend .ring{border-width:2px}
.legend .tri{border-left-width:7px;border-right-width:7px;border-bottom-width:12px;width:0;height:0}
/* timeline */
.tl{display:grid;border-top:2px solid var(--ink)}
.tl>div{border-bottom:1px solid var(--hair);padding:12px 6px;font-size:13.5px;display:flex;align-items:center}
.tl .yr{font-family:var(--serif);font-weight:900;font-size:17px;justify-content:center;border-bottom:2px solid var(--ink);color:var(--wine)}
.tl .yr.hd{justify-content:flex-start;color:var(--ink)}
.tl .nm{font-family:var(--serif);font-weight:900;font-size:20px}
.chip{padding:6px 8px;width:100%} .chip.w{background:var(--sky)} .chip.now{background:var(--butter);border:2px solid var(--orange);font-weight:700} .chip.none{color:var(--ink2)}
/* units */
.units{display:grid;gap:12px}
.ugrp{display:flex;flex-direction:column;gap:6px}
.ugrp h4{margin:0;font-size:14px;border-bottom:2px solid var(--ink);padding-bottom:4px;display:flex;justify-content:space-between;align-items:baseline}
.ugrp h4 b{font-family:var(--serif);font-size:24px;line-height:1}
.u{padding:8px;font-size:15px;font-weight:700;display:flex;justify-content:space-between;align-items:center}
.u.dk{color:var(--white)} .u .nb{font-family:var(--serif);font-size:12.5px}
/* directory */
.dir{display:grid;grid-template-columns:1fr 1fr;gap:22px}
.dir h3{font-family:var(--serif);font-size:21px;margin:0;border-bottom:2px solid var(--ink);padding-bottom:4px;display:flex;justify-content:space-between;align-items:baseline}
.dir h3 small{font-family:var(--sans);font-size:12px;font-weight:400;color:var(--ink2)}
.dir ol{list-style:none;margin:0;padding:0}
.dir li{display:grid;grid-template-columns:28px 70px 1fr;align-items:center;gap:6px;padding:5px 0;border-bottom:1px solid var(--hair);font-size:13.5px}
.dir li .n{font-family:var(--serif);font-weight:900;color:var(--wine);font-size:16px}
.dir li b{font-size:15.5px}
.tg{font-size:11.5px;padding:1px 6px;font-weight:700;white-space:nowrap}
.tg.inc{background:var(--wine);color:var(--white)} .tg.re{background:var(--orange)} .tg.up{background:var(--sky)} .tg.new{background:var(--butter)}
/* li chart */
.lic{display:flex;flex-direction:column}
.lic .r{display:grid;grid-template-columns:58px 1fr 210px;gap:10px;align-items:center;padding:4px 0;border-bottom:1px solid var(--hair);font-size:13px}
.lic .r.hd{font-size:11.5px;color:var(--ink2);border-bottom:2px solid var(--ink)}
.lic .l{font-family:var(--serif);font-weight:900;font-size:15px}
.lic .tr{height:20px;background:var(--track);position:relative}
.lic .f{position:absolute;inset:0 auto 0 0;background:var(--sky)}
.lic .f.out{background:var(--orange)}
.lic .f.unc,.hatch{background:repeating-linear-gradient(45deg,var(--sky),var(--sky) 5px,var(--white) 5px,var(--white) 10px)}
.hatch{display:inline-block;width:12px;height:12px}
.lic .p{position:absolute;left:6px;top:2px;font-size:11.5px;color:var(--ink)}
.lic .cand{font-size:12.5px;line-height:1.35}
/* svg graphs */
svg.net{width:100%;height:auto;max-height:100%;font-family:var(--sans)}
svg .edge{fill:none;stroke:var(--orange);stroke-linecap:round}
svg .edge.thin{stroke-width:3}
svg .elab{font-family:var(--serif);font-weight:900;font-size:16px;fill:var(--wine);paint-order:stroke;stroke:var(--paper);stroke-width:5px}
svg .n1{fill:var(--wine)} svg .n1t{fill:var(--white);font-size:14px;font-weight:700}
svg .n2{fill:var(--sky)} svg .n2t{fill:var(--ink);font-size:15px;font-weight:700}
svg .box{fill:var(--white);stroke:var(--ink);stroke-width:1}
svg .bn{fill:var(--ink);font-size:13.5px;font-weight:700} svg .bs{fill:var(--ink2);font-size:11.5px}
svg .hub{fill:var(--butter);stroke:var(--orange);stroke-width:3} svg .hubt{fill:var(--wine);font-size:17px;font-weight:900;font-family:var(--serif)}
svg .colh{fill:var(--wine);font-size:14px;font-weight:700;letter-spacing:.1em}
svg .e-wine{stroke:var(--wine);opacity:.8} svg .e-orange{stroke:var(--orange)} svg .e-sky{stroke:var(--sky)}
svg .t-wine{fill:var(--wine)} svg .t-orange{fill:var(--orange)} svg .t-sky{fill:var(--sky);stroke:var(--ink);stroke-width:.5}
svg .tt-wine{fill:var(--white);font-size:14px;font-weight:700} svg .tt-orange,svg .tt-sky{fill:var(--ink);font-size:14px;font-weight:700}
/* checklist */
.ck{display:grid;grid-template-rows:repeat(3,1fr);gap:12px;flex:1}
.ck>div{display:grid;grid-template-columns:100px 1fr;align-items:center}
.ck .kicknum{text-align:center}
.ck b{display:block;font-family:var(--serif);font-size:24px} .ck small{font-size:14px;color:var(--ink2)}
/* cover */
.cover{background:var(--sky)}
.cover .bigt{font-family:var(--serif);font-weight:900;font-size:112px;line-height:.95;color:var(--wine);margin:10px 0 6px}
.cover .bigt span{display:block;font-size:50px;line-height:1.2;color:var(--ink);margin-top:36px}
.cover .ribbon{align-self:flex-start;background:var(--wine);color:var(--white);font-family:var(--serif);font-size:26px;font-weight:900;padding:10px 20px;margin-top:14px}
.cover .claim{font-family:var(--serif);font-size:18px;max-width:640px;margin:18px 0 0}
.cover .lines{position:absolute;right:56px;top:96px;width:340px;background:var(--paper);padding:18px 22px;border-top:8px solid var(--orange)}
.cover .lines h5{margin:0 0 6px;font-size:12px;letter-spacing:.2em;color:var(--wine)}
.cover .ln{font-family:var(--serif);font-size:18px;font-weight:700;padding:8px 0;border-bottom:1px solid var(--hair);display:flex;gap:12px;align-items:baseline}
.cover .ln i{font-style:normal;font-size:26px;color:var(--wine);font-weight:900;min-width:44px}
.cover .ln:first-of-type i{font-size:16px}
.cover .fine{position:absolute;left:56px;bottom:46px;margin:0;padding:0;list-style:none;font-size:13px;line-height:1.7}
/* nav */
#nav{position:fixed;bottom:14px;right:18px;display:flex;gap:8px;align-items:center;font-size:14px;color:var(--ink2);z-index:5}
#nav button{font:inherit;border:1px solid var(--wine);background:var(--paper);color:var(--wine);padding:6px 12px;cursor:pointer}
#nav button:hover{background:var(--butter)}
#progress{position:fixed;top:0;left:0;height:4px;background:var(--orange);z-index:5}
#toc{position:fixed;top:12px;left:16px;z-index:5}
#toc select{font:inherit;font-size:14px;padding:5px 8px;border:1px solid var(--wine);background:var(--paper);color:var(--ink);max-width:260px}
@media (max-width:820px){
  body{overflow:auto}
  #stage{position:static;display:block;padding:12px 16px 40px}
  #deck{width:auto;height:auto;transform:none!important}
  .slide{position:relative;display:flex!important;padding:20px 16px 16px;margin-bottom:16px}
  h2{font-size:24px}
  .spread{grid-template-columns:1fr;gap:18px}
  .fig{border:none;padding:0} .txt{padding:0}
  .units{grid-template-columns:1fr 1fr!important}
  .dir{grid-template-columns:1fr}
  .hb .r{grid-template-columns:70px 1fr 100px;font-size:12.5px}
  .lic .r{grid-template-columns:48px 1fr} .lic .cand{grid-column:1/-1}
  .donutrow{flex-direction:column;align-items:stretch} .donut{width:200px;height:200px;margin:0 auto} .donut:after{inset:46px}
  .tl>div{font-size:11.5px;padding:6px 3px} .tl .nm{font-size:15px}
  .vc{min-height:220px;gap:8px;padding:0 2px} .gc{min-height:220px;gap:10px}
  .vc .cl{white-space:normal;font-size:11px;text-align:center;width:100%;bottom:-30px;line-height:1.2}
  .vc .num{font-size:20px}
  .ck{grid-template-rows:none;flex:none} .ck>div{grid-template-columns:64px 1fr;padding:12px 8px} .ck .kicknum{font-size:36px} .ck b{font-size:18px}
  .cover .bigt{font-size:60px} .cover .bigt span{font-size:28px}
  .cover .lines,.cover .fine{position:static;width:auto;margin-top:16px}
  .folio{position:static;margin-top:16px;flex-direction:column}
  #nav,#progress,#toc{display:none}
}
@media print{
  @page{size:1280px 720px;margin:0}
  body{background:var(--white);overflow:visible;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  #stage{position:static;display:block} #deck{transform:none!important;height:auto}
  .slide{display:flex!important;position:relative;width:1280px;height:720px;break-after:page}
  #nav,#progress,#toc{display:none}
  .qz details{display:block} .qz details>*{display:block}
}
/* 教學：學習目標、小測驗 */
.goals{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:12px;flex:1;justify-content:center;counter-reset:g}
.goals li{display:grid;grid-template-columns:72px 1fr;align-items:center;background:var(--sky);padding:14px 18px;counter-increment:g}
.goals .kicknum:before{content:counter(g)}
.goals.dense{gap:7px} .goals.dense li{padding:7px 16px;grid-template-columns:56px 1fr} .goals.dense .kicknum{font-size:34px} .goals.dense b{font-size:18px}
.goals li:nth-child(2){background:var(--butter)} .goals li:nth-child(3){background:var(--track)}
.goals small{display:block;font-size:12.5px;letter-spacing:.14em;color:var(--ink2)}
.goals b{display:block;font-family:var(--serif);font-size:22px;line-height:1.35}
.qz{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}
.qz .qtag{align-self:flex-start;background:var(--orange);color:var(--ink);font-weight:800;font-size:13px;letter-spacing:.14em;padding:3px 10px}
.qz .q{font-family:var(--serif);font-size:26px;font-weight:900;line-height:1.35;margin:0}
.qz .opts{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:1fr 1fr;gap:8px}
.qz .opts li{display:flex;gap:10px;align-items:center;border:1px solid var(--hair);background:var(--white);padding:10px 12px;font-size:17px}
.qz .opts b{font-family:var(--serif);color:var(--wine);font-size:20px}
.qz details{border-top:2px solid var(--ink);padding-top:8px}
.qz summary{cursor:pointer;font-weight:800;color:var(--wine);font-size:15px}
.qz details p{margin:6px 0 0;font-size:16px;line-height:1.5}
@media (max-width:820px){ .goals b{font-size:17px} .goals li{grid-template-columns:48px 1fr} .qz .q{font-size:20px} .qz .opts{grid-template-columns:1fr} }
</style>
</head>
<body>
<div id="progress"></div>
<div id="toc"><select id="tocSel" aria-label="跳至投影片"></select></div>
<div id="stage"><div id="deck">
__SLIDES__
</div></div>
<div id="nav"><button id="prev" aria-label="上一張">‹ 上一張</button><span id="count"></span><button id="next" aria-label="下一張">下一張 ›</button></div>
<script>
(function(){
  var $=function(i){return document.getElementById(i)};
  var slides=[].slice.call(document.querySelectorAll('.slide')),deck=$('deck'),i=0,sel=$('tocSel');
  slides.forEach(function(s,k){var o=document.createElement('option');o.value=k;o.textContent=(k+1)+'. '+s.dataset.title;sel.appendChild(o)});
  function show(n){i=Math.max(0,Math.min(slides.length-1,n));slides.forEach(function(s,k){s.classList.toggle('active',k===i)});
    $('count').textContent=(i+1)+' / '+slides.length;$('progress').style.width=((i+1)/slides.length*100)+'%';sel.value=i;
    try{history.replaceState(null,'','#'+(i+1))}catch(e){}}
  function fit(){deck.style.transform='scale('+Math.min(innerWidth/1320,innerHeight/770)+')'}
  $('prev').onclick=function(){show(i-1)};$('next').onclick=function(){show(i+1)};
  sel.onchange=function(){show(+sel.value);sel.blur()};
  document.addEventListener('keydown',function(e){if(e.target===sel)return;
    if(['ArrowRight','PageDown',' ','Enter'].indexOf(e.key)>-1){e.preventDefault();show(i+1)}
    else if(['ArrowLeft','PageUp','Backspace'].indexOf(e.key)>-1){e.preventDefault();show(i-1)}
    else if(e.key==='Home')show(0);else if(e.key==='End')show(slides.length-1)});
  deck.addEventListener('click',function(e){if(innerWidth<=820)return;var r=deck.getBoundingClientRect(),x=e.clientX-r.left;
    if(x<r.width*.2)show(i-1);else if(x>r.width*.8)show(i+1)});
  var tx=null;document.addEventListener('touchstart',function(e){tx=e.touches[0].clientX},{passive:true});
  document.addEventListener('touchend',function(e){if(tx===null||innerWidth<=820)return;var dx=e.changedTouches[0].clientX-tx;if(Math.abs(dx)>50)show(i+(dx<0?1:-1));tx=null});
  addEventListener('resize',fit);fit();var h=parseInt((location.hash||'').slice(1),10);show(isNaN(h)?0:h-1);
})();
</script>
</body>
</html>
