#! /usr/bin/perl
use strict; use warnings;
use List::Util qw(shuffle);
use File::Spec;
# Todo: deal with final shorts; Eco645.13.LysR_substrate|Tnp_2 should be called Eco645.13.T as tandem

my ($cutoff, $maxIsle, $criterion, $verbose) = (0.51, 200000, 'bestSupp', 1); 
warn "Called '$0 @ARGV' on " . localtime . "\n" if $verbose;
die "Usage: $0 mode[tiger/islander/mixed] logic[strict/lenient]\nLaunch from within genome directory\n" unless @ARGV == 2;
my %mode; if ($ARGV[0] eq 'tiger') {%mode = (tiger => 1)} elsif ($ARGV[0] eq 'islander') {%mode = (islander => 1)} else {%mode = (tiger => 1, islander => 1)}
my $logic = ($ARGV[1] eq "strict") ? 1 : 0;
my $minIsle = ($logic) ? 5000 : 2000;

my $dir = File::Spec->rel2abs($0); $dir =~ s/([^\/]+)$//;
#$mode{superpositive} = '';  # File with new names scores
my ($nick, %isl, %ends, $endorder, %tandems, %seen, %tandemtypes, %ct, %rejects, %splits, %dnas, %draws, %segCts, %trnas, %uniqIsles, %contexts, $org, %gnm, %tandCur, %serials, %rrna);
my (@dnaRA, %hskpEnrich, %fornEnrich, %stats, $in, %prevScores, %oldprevs, @order, @annots);
my (%is607, %supconfl, %skipInt, %litProv);
my %aalookup = qw/Ala A Arg R Asn N Asp D Cys C Glu E Gln Q Gly G His H Ile I Ile2 J Leu L Lys K Met M Phe F Pro P Ser S Thr T Trp W Tyr Y Val V Pyl O SeC U SeC(p) U tmRNA Z iMet B fMet B Sup X Undet ?/;

LoadContexts();
my $intList = IntList();
LoadPrevScores(); 
LoadTrna();
Load_tax();
LoadSupConfl(); 
#LoadIS607(); 
LoadTandemCurate();
Load_housekeep_enrich();
if ($mode{islander}) {
 for my $file (qw/islander.gff/) {Islander($file)}
 EndCt();
 FreshTandem();
}
if ($mode{tiger}) {
 for my $file (qw/genome.island.merge.gff/) {Tiger($file)}
 EndCt();
}
if ($mode{tiger} and $mode{islander}) {
 #TrnaStepoverTest();
 while (1) {my $change = TandemBuildTrna(); last if $change == 0}
}
ReInt();
if ($mode{tiger} and $mode{islander}) {
 if (defined $mode{superpositive}) {my $superpos = Superpositives($mode{superpositive}); exit}
 EndTrna();
 my $ttot = 0; for (keys %tandems) {$ttot += keys %{$tandems{$_}}} warn "$ttot tandems\n" if $verbose;
 TandemSplit();
 TandemDeoverlap('multi');
}
if ($mode{tiger}) {TandemBuildCompOnly()}  # Treat comps that didn't fit into islr tandems
TandemSplit();  # All tandems
TandemDeoverlap('multi');
Write();

# SUBROUTINES
sub LoadTandemCurate {for (@{ReadFile("$dir/../db/tandems.curate")}) {chomp; my @f = split "\t"; $tandCur{$f[0]} = $f[1]}}
#sub LoadIS607 {for (@{ReadFile("$dir/../db/is607.clade")}) {chomp; next unless /^([^\.]+)\.(Resolvase.*)/; $is607{$1}{$2} ++}}  # Tsc2.Resolvase.1
sub LoadSupConfl {my $i = 0; for (@{ReadFile("$dir/../db/raw.sup.conflict")}) {chomp; $i++; for (split /\s+/) {$supconfl{$_} = $i}}}  # Sfl26.24P:653765-677699(5)
sub LoadContexts {for (@{ReadFile("$dir/../db/contextnames.txt")}) {$contexts{$1} = $2 if /(\S+)\t(\S+)/}}
sub Load_housekeep_enrich {
 for (@{ReadFile("$dir/../db/housekeep_enrich.txt")}) {$hskpEnrich{$1} = $2 if /(\S+)\t(\S+)/}
 for (@{ReadFile("$dir/../db/foreign_enrich.txt")})   {$fornEnrich{$1} = $2 if /(\S+)\t(\S+)/}
}

sub Load_tax {
 my @taxa = qw/? ? ? ? ? ? ? ?/;
 $nick = "No_Nick";
 for (@{ReadFile("genome.tax")}) {
  my @f = split "\t";
  @taxa = (split(';', $f[2]), $f[1]);
  $nick = $f[4];
  #push @taxa, $f[1];
 }
 for (qw/division phylum order class family genus species org/) {$org .= "$_=" . shift(@taxa) . ";"}
}

sub LoadTrna {  # Change to marking oneLetter+q for questionable?
 open IN, "trna/ttm.gff" or die "Can't open ttm.gff\n";
 while (<IN>) {
  my @f = split "\t";
  my $id = 'Z';
  $id = $aalookup{$1} if /aa=([^;]+)/;
  #die "'$id'\n";
  $id = '?' if /questionable=[^;]/;
  #$trnas{$f[0]}[-1]{id} = scalar(@{$trnas{$f[0]}}) . $id;
  push @{$trnas{$f[0]}}, {L => $f[3], R => $f[4], id => 1 + scalar(@{$trnas{$f[0]}}) . $id};
 }
 close IN;
}

sub Load_dna {
 for (@{ReadFile("genome.stats")}) {
  next unless s/^(\S+)\t//; 
  my $dna = $1;
  next if $dna eq 'all';
  for my $cat (qw/len circ replicon cds pfam hypoth hskp forn/) {$stats{$dna}{$cat} = $1 if s/^(\S+)\t//}
  @{$stats{$dna}{dnaRA}} = ($_[0], split "\t"); # relative abundances of C and key dinucleotides
  @{$stats{$dna}{annots}} = (); 
 }
 for (@{ReadFile("genome.gff")}) {
  my @f = split "\t";
  my %l = (dna => $f[0], source => $f[1], type => $f[2], L => $f[3], R => $f[4], supp => $f[5], orient => $f[6], line => $_);
  for (split ';', $f[8]) {$l{$1} = $2 if /^([^=]+)=([^;]+)/}
  push @{$stats{$f[0]}{annots}}, \%l;
 }
 my $dna = '';
 for (@{ReadFile("genome.fa")}) {
  #next unless /^>(\S+)/;
  $dna = $1 , next if /^>(\S+)/;
  chomp;
  $stats{$dna}{seq} .= $_;
 }
}

sub ReInt {
 for my $dna (keys %isl) {
  for my $isle (keys %{$isl{$dna}}) {
   my ($endL, $endR) = (@{$isl{$dna}{$isle}}{qw/endL endR/});
   my ($ints, $deltaside, $deltaint) = IntOverlap($dna, $endL, $endR);
   @{$prevScores{$dna}{$endL}{$endR}}{qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/} = Scores($dna, $endL, $endR, -1) unless $prevScores{$dna}{$endL}{$endR}{logscore};
   @{$prevScores{$dna}{$endL}{$endR}}{qw/ints deltaside deltaint/} = IntOverlap($dna, $endL, $endR);
   @{$prevScores{$dna}{$endL}{$endR}}{qw/overall logscore/} = Score(@{$prevScores{$dna}{$endL}{$endR}}{qw/len deltaint foreign housekeep hypoth delta_GC dinuc/});
  }
 }
}
sub Superpositives {
 my (%superpos, %new);
 if ($_[0]) {my $file = $_[0]; for (@{ReadFile($file)}) {my @f = split "\t"; my $name = ''; $name = $1 if /ID=([^;]+)/; $new{$f[0]}{$f[3]}{$f[4]} = "name=$name;score=$f[5];"}}
 for my $dna (sort keys %isl) {
  my @order = sort {$isl{$dna}{$a}{endL} <=> $isl{$dna}{$b}{endL} || $isl{$dna}{$a}{endR} <=> $isl{$dna}{$b}{endR}} keys %{$isl{$dna}};
  for my $isle1 (@order) {
   next if $isl{$dna}{$isle1}{rejectnow};
   @{$isl{$dna}{$isle1}}{qw/superpositive superposConflict/} = ('',[]);
   my ($source1, $endL, $endR) = (@{$isl{$dna}{$isle1}}{qw/source endL endR/});
   for my $isle2 (@order) {
    next if $isl{$dna}{$isle2}{rejectnow} or $isle1 eq $isle2;
    next unless $endL eq $isl{$dna}{$isle2}{endL} and $endR eq $isl{$dna}{$isle2}{endR};
    my $source2 = $isl{$dna}{$isle2}{source};
    if ($source1 eq $source2) {
     #warn "$source1=$source2: $isl{$dna}{$isle1}{ID} $isl{$dna}{$isle2}{ID}\n";
     $isl{$dna}{$isle1}{supp} += $isl{$dna}{$isle2}{supp};
     $isl{$dna}{$isle2}{rejectnow} = 1; next
    } elsif ($source1 eq 'Islander') {$superpos{"$dna:$isle1"} ++}
    $isl{$dna}{$isle1}{superpositive} = $isl{$dna}{$isle2}{ID} unless $isl{$dna}{$isle1}{superpositive};
   }
   @{$prevScores{$dna}{$endL}{$endR}}{qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/} = Scores($dna, $endL, $endR, -1) unless $prevScores{$dna}{$endL}{$endR}{logscore};
   $isl{$dna}{$isle1}{isleScore} = -1 * $prevScores{$dna}{$endL}{$endR}{logscore};
  }
  for my $isle1 (@order) {
   #next if $isl{$dna}{$isle1}{rejectnow} or $isl{$dna}{$isle1}{source} eq 'Islander' or not $isl{$dna}{$isle1}{superpositive};  # TIGER superpositives only
   next if $isl{$dna}{$isle1}{rejectnow};  # raw.gff
   my ($source1, $endL, $endR) = (@{$isl{$dna}{$isle1}}{qw/source endL endR/});
   for my $isle2 (@order) {
    next if $isl{$dna}{$isle2}{rejectnow} or $isle1 eq $isle2 or $isl{$dna}{$isle2}{source} eq 'Islander' or not $isl{$dna}{$isle2}{superpositive};
    next if $endL >= $isl{$dna}{$isle2}{endR} or $endR <= $isl{$dna}{$isle2}{endL};
    push @{$isl{$dna}{$isle1}{superposConflict}}, $isl{$dna}{$isle2}{ID};
   }
   $dna =~ /^([^\.]+)/;
   #my @is607; for (split ',', $prevScores{$dna}{$endL}{$endR}{ints}) {/^([^:]+)/; push @is607, $1 if $is607{$nick}{$1}}
   #unless ($isl{$dna}{$isle1}{target}) {$isl{$dna}{$isle1}{target}; }
   for (qw/intList delta_int logscore brief/) {$isl{$dna}{$isle1}{line} =~ s/;$_=[^;]+;/;/;}
   for (qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall/) {$isl{$dna}{$isle1}{line} =~ s/;$_=[^;]+;/;/; $isl{$dna}{$isle1}{line} .= "$_=$prevScores{$dna}{$endL}{$endR}{$_};"}
   $isl{$dna}{$isle1}{line} =~ s/^(\S+\t\S+\t\S+\t)\S+\t\S+/$1$isl{$dna}{$isle1}{endL}\t$isl{$dna}{$isle1}{endR}/;
   print "$isl{$dna}{$isle1}{line}"; for (qw/supp superpositive isleScore/) {print "$_=$isl{$dna}{$isle1}{$_};"}
   print "superposConflict=", join(',',  @{$isl{$dna}{$isle1}{superposConflict}}), ";";
   print $new{$dna}{$endL}{$endR} if $new{$dna}{$endL}{$endR};
   print "\n";
   #exit;
  }
 }
 warn scalar(keys %superpos), " Superpositives\n"; exit;
}

sub Write {
 warn "Write\n" if $verbose;
 my %outIsles;
 my %splitIsles;
 for my $dna (sort keys %tandems) {
  $dna =~ /^([^\.]+)/;
  #warn "$nick bestSupp $gnm{bestSupp}\n" if $gnm{bestSupp}; warn "$nick bestRejected $gnm{bestRejected}\n" if $gnm{bestRejected};
  #Load_tax() unless $org;
  for my $tand (sort {$tandems{$dna}{$a}{spans}[0]{L} <=> $tandems{$dna}{$b}{spans}[0]{L}} keys %{$tandems{$dna}}) {
   my $t = $tandems{$dna}{$tand};
   #warn "Writing $$t{id}\n";
   my $finalCt = scalar(@{$$t{spans}});
   my ($rejectStatement, $segct) = ('', scalar(@{$$t{segments}})); #die "$segct segments in $$t{id}\n";
   #die "$$t{id}\n" unless $dnas{$dna}{org} and $$t{id} and $segct and $$t{members} and $$t{spans};
   $org =~ /org=([^;]+)/;
   my $header = "$nick $1   $dna:$$t{id}   $segct segments, " . scalar(keys %{$$t{members}}) . " input calls, $finalCt final calls";
   die "$header\nrejected_by=$$t{rejected_by}\n" if $$t{rejectees}{$$t{rejected_by}};
   #$$t{rejected_by} = "bestRejected:$gnm{bestRejected}" if $gnm{bestRejected} and $$t{bestSupp} < $gnm{bestRejected} and $$t{bestSupp} != 0 and not $$t{rejected_by};
   if ($$t{other}{rejected_by}) { $$t{rejected_by} .= "OtherContig_$$t{other}{rejected_by},"; $$t{rejectees}{OtherConitg} ++; } 
   if ($$t{rejected_by}) {$rejectStatement .= "Rejected by $$t{rejected_by}\n"}
   if (keys %{$$t{rejectees}}) {$rejectStatement .= "Caused rejection of " . join(', ', keys %{$$t{rejectees}}) . "\n"}
   warn "$$t{id}: $rejectStatement\n" if $$t{rejected_by};
   next if $$t{rejected_by};
   @{$$t{spans}} = sort {$$a{L} <=> $$b{L}} @{$$t{spans}};
   my ($ct, @targets)= (0);
   for my $span (@{$$t{spans}}) {
    $ct ++;
    $$span{supp} = 0;
    if ($$span{TIGER}) {for (@{$$span{TIGER}}) {$$span{supp} += $isl{$dna}{$_}{supp}}}
   }
   @{$$t{spans}} = sort {$$b{supp} <=> $$a{supp}} @{$$t{spans}};
   for my $s1 (@{$$t{spans}}) {
    next if $$s1{reject};
    $$s1{used} = 1;
    for my $s2 (@{$$t{spans}}) {
     next if $$s2{reject} or $$s2{used};
     next unless $$s1{L} < $$s2{R} or $$s1{R} > $$s2{L};
     $$s2{reject} = 1;
    }
   }
   @{$$t{spans}} = sort {$$a{L} <=> $$b{L}} @{$$t{spans}};
   for my $span (@{$$t{spans}}) {
    next if $$span{reject};
    if ($$t{sources}{TIGER} and not $$t{sources}{Islander} and not $$span{source} eq 'Inferred') {$isl{$dna}{$$span{TIGER}[0]}{brief} =~ /^\d+\.(.*)/; push @targets, $1}
   }
   my $target = '?';
   if ($$t{target}) {$target = $$t{target}}
   elsif ($$t{sources}{TIGER} and not $$t{sources}{Islander} and scalar(@targets) > 1) {$target = join(',', sort ($targets[0], $targets[-1]))}
   elsif ($targets[0]) {$target = $targets[0]}
   else {
    my %targetIsl;
    for my $isle (keys %{$$t{members}}) {$targetIsl{$isl{$dna}{$isle}{target}}++;}
    @targets = keys %targetIsl;
    $target = join(',', sort @targets) if @targets;
   }
   #warn "Targets - $$t{id}: @targets\n";
   #if ($target =~ /,/) {warn "comma left in target $target\n"}
   if ($target =~ /,/) {if ($tandCur{$target}) {$target = $tandCur{$target}} else {warn "comma left in target $target\n"}}
   $target =~ s/\([^\(]+\)//g;
   #warn "$$t{id} - $target: $rejectStatement\n" if $$t{rejected_by};
   #next if $$t{rejected_by};
   my $context = $target; $context = $contexts{$target} if $contexts{$target};
   #$context =~ s/^X$/Z/;
   $ct = 0;
   for my $span (@{$$t{spans}}) {
    next if $$span{reject};
    warn "Span $$span{id}\n";
    $ct ++;
    my $trunc_len = sprintf('%0.f', ($$span{len})/1000);
    warn "$$t{id}:$$span{id} too short" if $$span{len} < $minIsle and not $splitIsles{$$span{id}};
    next if $$span{len} < $minIsle and not $splitIsles{$$span{id}};
    my $overlap = "OLL=$ends{$dna}{$$span{L}}{L};OLR=$ends{$dna}{$$span{L}}{R};ORL=$ends{$dna}{$$span{R}}{L};ORR=$ends{$dna}{$$span{R}}{R};";
    $overlap .= "IslCenter=$ends{$dna}{$$span{L}}{center};" if $ends{$dna}{$$span{L}}{center};
    $overlap .= "IslCenter=$ends{$dna}{$$span{R}}{center};" if $ends{$dna}{$$span{R}}{center};
    my $orig = '';
    if ($$span{Islander}) {
     my $source = $$span{Islander}[0];
     for (qw/int_site int_site_type trna_dupe tRNA_len qStart qEnd bit_score/) {$orig .= "$_=$isl{$dna}{$source}{$_};"}
    }
    if ($$span{TIGER}) {
     my ($source, $best);
     for (@{$$span{TIGER}}) {unless ($best and $best > $isl{$dna}{$_}{supp}) {$best = $isl{$dna}{$_}{supp}; $source = $_}}
     #for (qw/contextsum refannot isleLseq unintSeq isleRseq gnm OL OU OR crossover/) {$orig .= "$_=$isl{$dna}{$source}{$_};"}
     for (qw/isleLseq unintSeq isleRseq gnm OL OU OR crossover/) {$orig .= "$_=$isl{$dna}{$source}{$_};"}
    }
    my $id = "$nick.$trunc_len.$context";
    $uniqIsles{$id} ++;
    if ($uniqIsles{$id} > 1) {
     if ($uniqIsles{$id} == 2) {
      my ($olddna);
      for my $dna2 (keys %outIsles) {
       next unless $outIsles{$dna2}{$id};
       $outIsles{$dna2}{$id}{line} =~ s/\tID=$id/\tID=$id.1/;
       $olddna = $dna2;
      }
      die "Can't find old dna for $id\n" unless $olddna;
     }
     $id .= ".$uniqIsles{$id}";
    }
    my $normsupp = 0; $normsupp = sprintf('%.2f', 100*$$span{supp}/$gnm{bestSupp}) if $$span{supp};
    #my @is607; for (split ',', $prevScores{$dna}{$$span{L}}{$$span{R}}{ints}) {/^([^:]+)/; push @is607, $1 if $is607{$nick}{$1}} my $is607 = join(',', @is607);
    my $line = join("\t", $dna, $$span{source}, 'island', $$span{L}, $$span{R}, sprintf('%.3f', -1*$$span{logscore}), $$t{orient}, $normsupp, '');
    $line .= "ID=$id;target=$target;$overlap$orig$org";
    for my $cat (qw/supp ints deltaside len deltaint foreign housekeep hypoth delta_GC dinuc overall logscore/) {$line .= "$cat=$$span{$cat};"}
    $line .= "rejectees=" . join(',', keys %{$$t{rejectees}}) . ";rejected_by=$$t{rejected_by};tandem=$$t{id}:$$span{id};tandem_power=$finalCt;tandem_pos=$ct;project=$$t{project};";
    die "No left span for $$span{id}" unless $$span{L};
    %{$outIsles{$dna}{$id}} = (L => $$span{L}, line => $line, org => $org, len => ($$span{R}-$$span{L}+1)) unless $splitIsles{$$span{id}};
    warn "Wrote $$t{id} - $id\n";
    if ($splitIsles{$$span{id}}) {
     for my $otherspan (@{$splitIsles{$$span{id}}}) {
      $outIsles{$$otherspan{dna}}{$$otherspan{id}}{line} .= "\tOTHER SPLIT\t$line";
      $outIsles{$$otherspan{dna}}{$$otherspan{id}}{len} += ($$span{R}-$$span{L}+1);
     }
    }
    if ($overlap =~ /IslCenter=/) { 
     warn "For $$t{id}:$$span{id}, checking:\n";
     for my $otherspan (@{$$t{other}{spans}}) {
      warn "$$t{other}{id}:$$otherspan{id}\n";
      if ($$otherspan{L} == $$t{other}{center} or $$otherspan{R} == $$t{other}{center}) {
       warn "$$t{other}{id}:$$otherspan{id} used\n";
       push @{$splitIsles{$$otherspan{id}}}, {dna => $dna, id => $id};
       last;
      }
     }
    }
   }
  }
 }
 open RES, ">resolve2.gff";
 for my $dna (sort keys %outIsles) {
  for my $id (sort {$outIsles{$dna}{$a}{L} <=> $outIsles{$dna}{$b}{L}} keys %{$outIsles{$dna}}) {
   warn "Island too short!\n", next if $outIsles{$dna}{$id}{len} < $minIsle;
   print RES "$outIsles{$dna}{$id}{line}\n";
  }
 }
 close RES;
 open OUT, ">prevScores.gff";
 for my $dna (sort keys %prevScores) {
  for my $L (sort {$a <=> $b} keys %{$prevScores{$dna}}) {
   for my $R (sort {$b <=> $a} keys %{$prevScores{$dna}{$L}}) {print OUT "$prevScores{$dna}{$L}{$R}{line}\n"}
  }
 } close OUT;
}

sub TandemBuildCompOnly {
 warn "TandemBuildCompOnly\n" if $verbose;
 my ($mode) = ($_[0]); 
 my %other;
 for my $dna (keys %ends) {
  my %islands;
  for (keys %{$ends{$dna}}) {  # For each vertex ...
   my ($end, $j) = ($_, $ends{$dna}{$_});
   for (@{$trnas{$dna}}) {next if $$_{R} < $$j{L}; last if $$_{L} > $$j{R}; $$j{trna}{$$_{id}} =1} #; warn "$dna $end:$$j{L}-$$j{R} multiTrna\n" if keys %{$$j{trna}} > 1}
   my ($tand, %jmembers, %jtands);
   my ($bestSupp, $totSupp, %flag, $orient) = (0,0);
   #print "$end $$j{supp}\n";
   for (keys %{$$j{members}}) {  # Islands using that vertex
    die "ERROR parsing island name $_ for end $end: $dna $_ $$j{L} $$j{R}\n" unless/(.*)([LR])$/;  # $1=island $2=side
    my ($isle, $side) = ($1, $2);
    #print "$end $_ $isle $isl{$dna}{$isle}{rejected_by}; $isl{$dna}{$isle}{tandem}\n";
    next if $isl{$dna}{$isle}{rejected_by} or $isl{$dna}{$isle}{tandem};  # Skip since previously evaluated as part of Islander tandem
    #$flag{old} ++, next if $isl{$dna}{$isle}{rejected_by} or $isl{$dna}{$isle}{tandem};  # Skip since previously evaluated as part of Islander tandem
    #$flag{new} ++;
    warn "Both ends of $dna/$isle $side $isl{$dna}{$isle}{L} $isl{$dna}{$isle}{R} in end $$j{coord}($$j{L}-$$j{R})\n" if $jmembers{$isle}; 
    $jmembers{$isle} ++;
    $jtands{$islands{$isle}} ++ if $islands{$isle};  # Tandem call for other island end?
    $isl{$dna}{$isle}{'end'.$side} = $$j{coord};  # Record ends for isls
    if ($bestSupp < $isl{$dna}{$isle}{supp}) {$bestSupp = $isl{$dna}{$isle}{supp}; $orient = $isl{$dna}{$isle}{orient}};
    $totSupp += $isl{$dna}{$isle}{supp};
    #die "$dna $_ $$j{L} $$j{R} $isl{$dna}{$isle}{supp} $bestSupp $totSupp\n";
   }  # Record as new or augmented tandem or merger
   next unless keys %jmembers;
   if (keys %jtands == 0) {$$j{founder} =~ /(.*)([LR])$/; $tand = $1; }  # Start new tandem
   else {$tand = (keys %jtands)[0]}  # Choose one at random
   #print "tand $tand best $bestSupp\n" if $end =~ /1996344|2027690|2039871|2044751/;
   if (keys %jtands > 1) {  # Merge from other(s) into chosen
    for my $old (keys %jtands) {
     #print "old $tandems{$dna}{$old}{bestSupp}, chosen $bestSupp" if $end =~ /1996344|2027690|2039871|2044751/;
     $totSupp += $tandems{$dna}{$old}{totSupp};
     $bestSupp = $tandems{$dna}{$old}{bestSupp}, $orient = $tandems{$dna}{$old}{orient} if $bestSupp < $tandems{$dna}{$old}{bestSupp};
     #print " > $bestSupp\n" if $end =~ /1996344|2027690|2039871|2044751/;
     next if $old eq $tand;
     for (keys %{$tandems{$dna}{$old}{members}}) {$tandems{$dna}{$tand}{members}{$_} =1; $islands{$_} = $tand}
     for (keys %{$tandems{$dna}{$old}{ends}}) {$tandems{$dna}{$tand}{ends}{$_} =1}
     delete $tandems{$dna}{$old};
    }
   }  # Add info to chosen tandem about this end (j)
   $tandems{$dna}{$tand}{ends}{$$j{coord}} ++;
   @{$tandems{$dna}{$tand}}{qw/bestSupp orient/} = ($bestSupp, $orient) if not defined $tandems{$dna}{$tand}{bestSupp} or $bestSupp > $tandems{$dna}{$tand}{bestSupp};
   $tandems{$dna}{$tand}{totSupp} += $totSupp;
   $tandems{$dna}{$tand}{dna} = $dna;
   #print "Current tand $tand best $tandems{$dna}{$tand}{bestSupp}, tot $tandems{$dna}{$tand}{totSupp}\n" if $end =~ /1996344|2027690|2039871|2044751/;
   for my $isle (keys %jmembers) {
    $tandems{$dna}{$tand}{sources}{$isl{$dna}{$isle}{source}} = 1;
    $tandems{$dna}{$tand}{project} = $isl{$dna}{$isle}{project};
    $tandems{$dna}{$tand}{members}{$isle} = 1;
    $islands{$isle} = $tand;
    if ($isl{$dna}{$isle}{other}) {
      $other{$isl{$dna}{$isle}{other}{ID}} = \%{$tandems{$dna}{$tand}};
    }
    $tandems{$dna}{$tand}{center} = $isl{$dna}{$isle}{center} if $isl{$dna}{$isle}{center};
   }
  }  # end
  for (keys %{$tandems{$dna}}) {
   my $t = $tandems{$dna}{$_};
   my @ends = sort {$a <=> $b} keys %{$$t{ends}};
   $$t{id} = "C$ends[0]-$ends[-1]($$t{bestSupp})" unless $$t{id};
   if ($$t{sources}{TIGER} and $$t{id} =~ s/^I/CI/) {}
   #warn "$$t{id}: @ends; $ends[0]-$ends[-1]($$t{bestSupp})\n";
   $$t{questionable} = 0;
   $$t{power} = scalar(@ends);
  }
 }  # dna
 for my $dna (keys %ends) {
  for my $tand (keys %{$tandems{$dna}}) {
   my $t = \%{$tandems{$dna}{$tand}};
   for (keys %{$$t{ends}}) {
    my $j = $ends{$dna}{$_};
    for (keys %{$$j{members}}) {
     next unless /(.*)([LR])$/;
     my $isle = $1;
     $$t{other} = \%{$other{$isl{$dna}{$isle}{ID}}} if $other{$isl{$dna}{$isle}{ID}};
    }
   }
  }
 }
}

sub TrnaStepoverTest {
 warn "TrnaStepoverTest\n" if $verbose;
 for my $dna (keys %ends) {
  for my $tand (keys %{$tandems{$dna}}) {
   my $t = \%{$tandems{$dna}{$tand}};
   my @tends = sort keys %{$$t{ends}};
   $$t{trnaStepoverTest} = sub {return 1 if shift() < $ends{$dna}{$tends[0]}{L}};
   $$t{trnaStepoverTest} = sub {return 1 if shift() > $ends{$dna}{$tends[-1]}{R}} if $$t{trnaSide} eq 'R';
  }
 }
}

sub TandemBuildTrna {  # Tandem count from Islander unchanged by Comp inclusion
 my ($mode, $change) = ($_[0], 0);
 my %other;
 for my $dna (keys %ends) {
  for my $tand (keys %{$tandems{$dna}}) {
   my $t = \%{$tandems{$dna}{$tand}};
   #warn "$tand\n";
   for (keys %{$$t{ends}}) { #$ends{$dna}}) {  # For each vertex ...
    my ($end, $j) = ($_, $ends{$dna}{$_});
    #warn "$end $$j{supp}\n";
    for (keys %{$$j{members}}) {  # Islands using that vertex
     #warn "$dna $end $_ $$j{L} $$j{R}\n";
     die "$dna $_ $$j{L} $$j{R}\n" unless/(.*)([LR])$/;  # $1=island $2=side
     my ($isle, $side, $otherside) = ($1, $2, $2); $otherside =~ tr/LR/RL/; $otherside = $isl{$dna}{$isle}{'end'.$otherside};
     next if &{$$t{trnaStepoverTest}}($otherside);  # Prevents tRNA stepover
     next if $$t{members}{$isle};
     next if $isl{$dna}{$isle}{group} and $isl{$dna}{$isle}{group} ne $tand;
     $change ++;
     warn "Both ends of $dna/$isle $side $isl{$dna}{$isle}{L} $isl{$dna}{$isle}{R} in end $$j{coord}($$j{L}-$$j{R})\n" if $otherside == $isl{$dna}{$isle}{'end'.$side};
     #warn "$dna $isle $side $end $isl{$dna}{$isle}{'end'.$side}\n";
     $isl{$dna}{$isle}{'end'.$side} = $end;  # Careful not to change between two tandems
     $$t{bestSupp} = $isl{$dna}{$isle}{supp} if $tandems{$dna}{$tand}{bestSupp} < $isl{$dna}{$isle}{supp};
     $$t{totSupp} += $isl{$dna}{$isle}{supp};
     $$t{ends}{$otherside} = 1;
     $$t{sources}{$isl{$dna}{$isle}{source}} = 1;
     $$t{members}{$isle} = 1;
     $$t{dna} = $dna;
     $$t{center} = $isl{$dna}{$isle}{center} if $isl{$dna}{$isle}{center};
     $$t{orient} = $isl{$dna}{$isle}{orient};
     if ($isl{$dna}{$isle}{other}) {
      $other{$isl{$dna}{$isle}{other}{ID}} = $t;
     }
    }
   }  # end
  }
  for (keys %{$tandems{$dna}}) {$tandems{$dna}{$_}{power} = scalar(keys %{$tandems{$dna}{$_}{ends}})}
 }  # dna
 for my $dna (keys %ends) {
  for my $tand (keys %{$tandems{$dna}}) {
   my $t = \%{$tandems{$dna}{$tand}};
   for (keys %{$$t{ends}}) {
    my $j = $ends{$dna}{$_};
    for (keys %{$$j{members}}) {
     next unless /(.*)([LR])$/;
     my $isle = $1;
     $$t{other} = \%{$other{$isl{$dna}{$isle}{ID}}} if $other{$isl{$dna}{$isle}{ID}};
    }
   }
  }
 }
 warn "TandemBuildTrna, $change changes\n" if $verbose; 
 return $change;
}

sub ReadFile {
 my @ret;
 #print "Reading file $_[0]\n" if $verbose;
 unless (open IN, $_[0]) {return \@ret;} #warn "Can't open $_[0]\n"; return \@ret;}
 while (<IN>) {next if /^#/; push @ret, $_}
 close IN; chomp @ret; return \@ret;
}

sub LoadPrevScores {  # Because score calculation is slow
 for (@{ReadFile("prevScores.gff")}) {
  my @f = split "\t";
  my $p = \%{$prevScores{$f[0]}{$f[3]}{$f[4]}};
  for my $cat (qw/ints deltaside len deltaint foreign housekeep hypoth delta_GC dinuc overall logscore/)
  {die "$f[8]\n" unless $f[8] =~ s/;$cat=([^;]*)//; $$p{$cat} = $1}
  ($$p{overall}, $$p{logscore}) = Score($$p{len}, $$p{deltaint}, $$p{foreign}, $$p{housekeep}, $$p{hypoth}, $$p{delta_GC}, $$p{dinuc});
  for my $cat (qw/len ints deltaside deltaint foreign housekeep hypoth delta_GC dinuc overall logscore/) {$f[8] .= "$cat=$$p{$cat};"}
  $$p{line} = join("\t", @f);
 }
}

sub TandemDeoverlap {
 my ($mode) = ($_[0]);
 warn "TandemDeoverlap\n" if $verbose;
 for my $dna (sort keys %tandems) {
  $dna =~ /^([^\.]+)/;
  my $d = $tandems{$dna};
  if ($mode eq 'multi') {@order = sort {
   $$d{$b}{bestSupp} <=> $$d{$a}{bestSupp} ||
   $$d{$a}{bestScore} <=> $$d{$b}{bestScore} ||
   $$d{$a}{questionable} <=> $$d{$b}{questionable} ||
   $$d{$b}{power} <=> $$d{$a}{power}
  } keys %{$d}}
  elsif ($mode eq 'FPformula') {@order = sort {$tandems{$dna}{$a}{bestScore} <=> $tandems{$dna}{$b}{bestScore}} keys %{$tandems{$dna}}}  # Lower overall => better island
  elsif ($mode eq 'random') {@order = shuffle keys %{$tandems{$dna}}}
  for my $i (0 .. $#order) {
   my ($tand, $t) = ($order[$i], $tandems{$dna}{$order[$i]});
   #$$t{rejected_by} = 'nospans', next unless $$t{spans};
   my $ci = ''; for (@{$$t{spans}}) {$ci .= "$$_{L}-$$_{R}," if $$_{source} eq 'TIGER,Islander'}
   #print scalar(@{$$t{spans}}), " $$t{id}, $$t{bestSupp}, $$t{bestScore}, $$t{spans}[0]{L}-$$t{spans}[-1]{R}, $$t{questionable}, $$t{power}\n";
   next if $$t{rejected_by};
   die "$$t{id} no bestSupport\n" unless defined $$t{bestSupp};
   #die "$$t{spans}\n";
   #next if $mode eq 'compSupport' and not $$t{sources}{TIGER};
   my @coords = ($$t{spans}[0]{L}, $$t{spans}[-1]{R});  # Termini of the trimmed tandem
   die "$$t{id} $coords[0] and $coords[1]\n" unless $coords[0] and $coords[1];
   my (%endcats, %endnos, $islandL, @out);
   for my $j ($i+1 .. $#order) {  # Overlaps others?
    my $t2 = $tandems{$dna}{$order[$j]};
    next if $$t{rejected_by};
    #next if $mode eq 'compSupport' and not $$t2{sources}{TIGER};
    my @coords2 = ($$t2{spans}[0]{L}, $$t2{spans}[-1]{R});
    warn "$dna $$t{id} coords=@coords vs $$t2{id} coords2=@coords2\n" unless $coords2[1];
    next if $coords[0] > $coords2[1] or $coords[1] < $coords2[0] or $$t2{rejected_by};
    #warn "t1($$t{id})}: $$t{bestSupp}, $$t{bestScore}, $$t{questionable}, $$t{power}\nt2($$t2{id}): $$t2{bestSupp}, $$t2{bestScore}, $$t2{questionable}, $$t2{power}\n\n";
    $gnm{bestRejected} = $$t2{bestSupp} unless $gnm{bestRejected} and $gnm{bestRejected} > $$t2{bestSupp} and $$t2{bestSupp} > 0;
    $$t2{rejected_by} = $$t{id};
    for (keys %{$$t2{members}}) {$isl{$dna}{$_}{rejected_by} .= ",$$t{id}"}
    $$t{rejectees}{$$t2{id}} ++;
    #print "$dna:$$t2{id} $$_{L}-$$_{R} rejected by $$t{id} with CIs $ci\n";
    #for (@{$$t2{spans}}) {die "$dna @coords, @coords2\n" unless $$_{source}; push @{$ct{CIrejects}}, "$dna:$$t2{id} $$_{L}-$$_{R} rejected by $$t{id} with CIs $ci" if $$_{source} eq 'TIGER,Islander'}
   }
   #die "$mode $$t{rejected_by}\n" if $$t{rejectees}{$$t{rejected_by}};
  }
 }
}

sub TandemSplit {
 warn "TandemSplit\n" if $verbose; 
 for my $dna (sort keys %tandems) {
  my $isleCt = 0;
  for (keys %{$tandems{$dna}}) {
   my ($tand, $t) = ($_, $tandems{$dna}{$_});
   next if $$t{spans};  # Skip previously processed
   #print scalar(keys %{$$t{members}}), " members in $$t{id}\n"; for (keys %{$$t{members}}) {print "$_\n";} print scalar(keys %{$$t{ends}}), " ends in $$t{id}\n";
   my ($L, @segments, %members, %coordpos, %othercoordpos, @coords, @othercoords, %supps, %segCt, @noInts, $noIntFlag, %cuts, @span, %usedTrna, @priorities);
   for (sort {$a <=> $b} keys %{$$t{ends}}) {warn "No end $_ for $tand $dna\n" unless $ends{$dna}{$_}; push @coords, $_; $coordpos{$_} = $#coords; $supps{$#coords} = $ends{$dna}{$_}{supp};} # print "$tand $_\n"
   for (sort {$a <=> $b} keys %{$$t{other}{ends}}) {push @othercoords, $_; $othercoordpos{$_} = $#othercoords;}
   for my $i (0..$#coords) {warn "test1: $dna $_ $i $#coords: @coords\n" unless defined $supps{$i}}
   #for (@coords) {print "$_\n"}
   $$t{rejected_by} = ''; %{$$t{rejectees}} = ();
   for my $isle (sort {$a <=> $b} keys %{$$t{members}}) {
    my $m = $isl{$dna}{$isle};
    #warn "$$m{ID}:$coordpos{$$m{endL}}-$coordpos{$$m{endR}}\n";
    @{$m}{qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/} = Span($dna, $$m{endL}, $$m{endR});
    die "$tand $$t{id} $dna $$m{endL} $coordpos{$$m{endL}} $$m{endR} $coordpos{$$m{endR}} $$m{L} $$m{R}; @coords\n" unless defined($coordpos{$$m{endL}}) and defined($coordpos{$$m{endR}});
    push @{$members{$coordpos{$$m{endL}}}{$coordpos{$$m{endR}}}}, $isle;
    #print "$$t{id} $isle $members{$coordpos{$$m{endL}}}{$coordpos{$$m{endR}}}[0] $$m{endL} $coordpos{$$m{endL}}, $$m{endR} $coordpos{$$m{endR}} $dna\n";
   }
   unless ($$t{id}) {  # TIGER-only islands get named now
    $$t{id} = "C$coords[0]-$coords[-1]($$t{$criterion})";
    die "compOnly contains islander $dna $$t{id}\n" if $$t{sources}{Islander};
   }
   #warn "Coords - $$t{id}: @coords\n";
   for my $i (0..$#coords) {  # Survey each segment for size, ints, find noInt segment blocks
    $L = $coords[$i];
    for my $j ($i+1..$#coords) {
     my $R = $coords[$j];
     if ($ends{$dna}{$R}{trna}) {for (keys %{$ends{$dna}{$R}{trna}}) {$usedTrna{$_} ++}}
     $L = $coords[0], next unless $L;  # Initialize L end island
     my $reject = '';
     my $len = $R - $L + 1;
     my ($ints, $deltaside, $delta) = IntOverlap($dna, $L, $R);
     $reject = 'short' if $len < $minIsle and not $$t{other}; # Shorts with ints are few, ignore in tandem-cutting, then warn if any products too short
     if ($ints) {
      unless ($noIntFlag) {$cuts{$coordpos{$L}} ++}
      $noIntFlag = 0;
     } else {
      my $otherints = IntOverlap($$t{other}{dna}, $othercoords[0], $othercoords[-1]) if $$t{other} and @othercoords;
     if ($otherints) {
       unless ($noIntFlag) {$cuts{$coordpos{$L}} ++}
       $noIntFlag = 0;
      }
      else {
       $reject = 'noInt';
       unless ($noIntFlag) {push @noInts, [$coordpos{$L}]}
       push @{$noInts[-1]}, $coordpos{$R};
       $noIntFlag ++;
      }
     }
     push @segments, {L => $L, R => $R, len => $len, ints => $ints, deltaside => $deltaside, delta => $delta, reject => $reject};
     #print "$#coords $reject $L $R\n";
     $segCts{$#coords}{$reject} ++;
    }
   }
   for my $i (0..$#coords) {warn "test2: $dna $_ $i $#coords: @coords\n" unless defined $supps{$i}}
   for my $s (@segments) {for (@{$trnas{$dna}}) {next if $$s{L} > $$_{R}; last if $$s{R} < $$_{L}; next if $usedTrna{$$_{id}}; $$s{trna}{$$_{id}} ++}}
   $cuts{$#coords} ++ unless @noInts and $noInts[-1][-1] == $#coords;  # Last coord unless already incorporated
   #for (sort {$a <=> $b} keys %cuts) {print "$_ $coords[$_]\n"}
   push @priorities, 0        if $$t{trnaSide} and $$t{trnaSide} eq 'L';  # Prevents tRNA loss for Islander tandems
   push @priorities, $#coords if $$t{trnaSide} and $$t{trnaSide} eq 'R';
   #print "$$t{id} @priorities\n";
   for my $i (@noInts) {for (sort {$supps{$b} <=> $supps{$a}} @{$i}) {if ($supps{$_} > 0) {
    push @priorities, $_; #print "priority supp:$supps{$_} node:$_\n";
   }}}  # Prioritize only non-zero supp ends
   #warn "Priorities - $$t{id}: @priorities\n";
   my @rounds = [['Lend']];  # array of rounds of splittings expansions, each round is array of arrays of cuts to test
   my $lastBreak = -1;
   if (@noInts and $noInts[0][0] != 0) {$lastBreak = $noInts[0][0]-1; $rounds[-1][-1][-1] = $coords[$lastBreak]}
   for my $i (@noInts) {
    #print "noInt @{$i}; $rounds[-1][-1][-1] $lastBreak\n";
    if ($$i[0] > $lastBreak+1) {  # New noInt group, process previous
     #print $lastBreak+1, " < $$i[0] so Process1\n";
     for (ProcessRound($dna, $coords[$lastBreak+1], 1, \@{$rounds[-1]}, \@priorities)) {
      #print "Process2: $_ '$coordpos{$_}'\n";
      #warn "Debug - $$t{id}: $_; $coordpos{$_}\n";
      $cuts{$coordpos{$_}} ++;
     }
     $lastBreak = $$i[0]-1;
     @rounds = [[$coords[$lastBreak]]];
    }
    push @rounds, [];
    my $priority;
    PRIORITY:
    for (@priorities) {for my $newR (@{$i}) {if ($newR == $_) {
     $priority = $_;
     #print "priority=$_\n";
     last PRIORITY;
    }}}
    for my $newR (@{$i}) {
     next if defined $priority and $newR != $priority;
     for my $prev (@{$rounds[-2]}) {
      push @{$rounds[-1]}, [@{$prev}, $coords[$newR]];
     }
    }
    $lastBreak = $$i[-1];
   }
   my $coord = 'Rend'; $coord = $coords[$lastBreak+1] if $lastBreak+1 <= $#coords;
   #print "done noInts; $dna $lastBreak $#coords $coord $rounds[-1][-1][-1]\n";
   unless ($lastBreak == -1) {for (ProcessRound($dna, $coord, 2, \@{$rounds[-1]})) {$cuts{$coordpos{$_}} ++;}}
   my @cuts = sort {$a <=> $b} keys %cuts;
   #for (@cuts) {print "$_\n"} exit;
   $L = ''; my $lastCut = $cuts[0];
   my $counts = 0;
   my $numCoordPos = scalar keys %coordpos;
   push @cuts, (0..$numCoordPos) if scalar @cuts == 0;
   #warn "Cuts - $$t{id}: @cuts";
   my @spans;
   for my $i (0..$#cuts) {
    $L = $coords[$cuts[$i]];
    for my $j ($i+1..$#cuts) {
     $counts++;
     my $R = $coords[$cuts[$j]];
     my $length = $R - $L + 1;
     #print "$_ $coords[$_] $L $R\n";
     my %source;
     push @{$$t{spans}}, {id => "$tand.$counts", L => $L, R => $R, posL => $lastCut, posR => $cuts[$j], len => $length};
     #warn "New Tandem Span - $$t{id}/$$t{spans}[-1]{id}:$L-$R;$coordpos{$L}-$coordpos{$R}\n";
     if ($members{$coordpos{$L}}{$coordpos{$R}}) {
      for (@{$members{$coordpos{$L}}{$coordpos{$R}}}) {
       die "$dna, $L, $R, $coordpos{$L}, $coordpos{$R}\n" unless $_;
       $source{$isl{$dna}{$_}{source}} ++;
       push @{$$t{spans}[-1]{$isl{$dna}{$_}{source}}}, $_;
       push @{$$t{spans}[-1]{members}}, $_;
       $isl{$dna}{$_}{tandem} = $tand;
       #warn "$isl{$dna}{$_}{ID}:$coordpos{$L}-$coordpos{$R}\n";
      }
     } else {$source{Inferred} ++;}
     $$t{spans}[-1]{source} = join(',', sort keys %source);
     #print "$$t{spans}[-1]{source} $$t{id} $dna $L $R\n";
     $isleCt ++;
     Span($dna, $L, $R) unless $prevScores{$dna}{$L}{$R};
     for (keys %{$prevScores{$dna}{$L}{$R}}) {$$t{spans}[-1]{$_} = $prevScores{$dna}{$L}{$R}{$_}}
     $$t{bestScore} = $$t{spans}[-1]{logscore} unless $$t{bestScore} and $$t{bestScore} < $$t{spans}[-1]{logscore};
     $lastCut = $cuts[$j];
    }
   }
   for my $L (keys %members) {for my $R (keys %{$members{$L}}) {for my $isle (@{$members{$L}{$R}}) {  # Reject original island to prevent reuse
    $isl{$dna}{$isle}{rejected_by} .= "split($tand)," unless $isl{$dna}{$isle}{tandem};
   }}}
   ($$t{segments}, $$t{cuts}, $$t{coords}, $$t{coordpos}, $$t{calls}) = (\@segments, \@cuts, \@coords, \%coordpos, \%members);
  }  # tandem
  #warn scalar(keys %{$tandems{$dna}}), " tandems in $dna, $isleCt isles\n";
 }  # dna
}

sub ProcessRound {
 my ($dna, $lastCut, $final, @splits, %best) = ($_[0], $_[1], $_[2]);
 my @round = @{$_[3]};
 #print "$final $dna $lastCut\n";
 for my $s (0..$#round) {
  my ($sum, $split, $priority) = (0, $round[$s], '');
  #print "split $s: @{$split}\n";
  push @{$split}, $lastCut;
  for my $i (1..$#{$split}) {
   my ($L, $R) = ($$split[$i-1], $$split[$i]);
   #die "$dna $L $final\n" unless $R;
   #print "element $i of split $s: $L $R\n";
   next if $L eq 'Lend' or $R eq 'Rend';
   for ($L, $R) {$splits[$s]{$_} ++}
   $sum += (Span($dna, $L, $R))[-1];
   #print "sum $i of split $s: $sum\n";
  }
  %best = (sco => $sum, split => $s) unless $best{sco} and $best{sco} < $sum;
 }
 #print "$dna $lastCut $best{sco} $best{split} ", keys(%{$splits[$best{split}]}), "\n";
 return keys %{$splits[$best{split}]};
}

sub Span {
 my ($dna, $L, $R) = @_;
 my $p = \%{$prevScores{$dna}{$L}{$R}}; my @out = ();
 @{$p}{qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/} = Scores($dna, $L, $R, -1) unless $$p{logscore};
 $$p{line} = join("\t", $dna, qw/TIGER island/, $L, $R, qw/. . . ID=;/);
 for (qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/) {push @out, $$p{$_}; $$p{line} .= "$_=$$p{$_};"}
 return @out;
}

sub DrawTandem {
 my ($dna, $header, $first, $last, $ret, $rej, %cuts) = ($_[0], $_[1], ${$_[4]}[0], ${$_[4]}[-1], '', $_[5]);
 my @segments = @{$_[2]};
 my @spans = @{$_[6]};
 my %members = %{$_[3]};
 for (@{$_[4]}) {$cuts{$_} ++}
 my ($n, $d, $p, $c, $s) = ('|', '|', '', '', '');  # n=segment deltaInt/reject, l=genome/tRNA line, d=segment lengths, p=pos, c=cuts, s=spans
 my ($l, $extra) = MultiT($dna, $segments[0]{L}); $rej .= $extra;
 for my $L (sort {$a <=> $b} keys %members) {
  #print "$L\n";
  my $startpad = ' ' x ($L * 8);
  for my $R (sort {$a <=> $b} keys %{$members{$L}}) {  # Top lines marking original calls
   #print "$R\n";
   for my $m (@{$members{$L}{$R}}) {  # Could be both islander and TIGER here
    #print "$m\n";
    my $len = ($R-$L) *8;
    $ret .= $startpad;
    if ($isl{$dna}{$m}{source} eq 'Islander') {$ret .= '=' x $len}
    else {$ret .= '-' x $len}
    $ret .= " $isl{$dna}{$m}{supp}, " . sprintf('%.2f', $isl{$dna}{$m}{logscore}) . " $isl{$dna}{$m}{brief}\n";
   }
  }
 }
 for my $i (0..$#segments) {  # n, l, d, p, c
  my @a = split //, '       |';
  if ($segments[$i]{reject} eq 'noInt') {$a[3] = 'N'}
  elsif ($segments[$i]{reject} eq 'short') {$a[3] = 'S'}
  if ($segments[$i]{deltaside} =~ /L/) {$a[0] = 'i'}
  if ($segments[$i]{deltaside} =~ /R/) {$a[6] = 'i'}
  $n .= join '', @a;
  my @ladd = split //, '_______|';
  $ladd[3] = 't' if $segments[$i]{trna};
  if ($ends{$dna}{$segments[$i]{R}}{trna}) {my ($trna, $extra) = MultiT($dna, $segments[$i]{R}); $ladd[7] = $trna; $rej .= $extra}
  $l .= join '', @ladd;
  my $seg = ' ' . $segments[$i]{len};
  while (length $seg < 7) {$seg .= ' '}  # Pad
  $d .= $seg . '|';
  $seg = $segments[$i]{L};
  while (length $seg < 8) {$seg .= ' '}  # Pad
  $p .= $seg;
  if ($cuts{$i}) {$c .= '|'} elsif ($i < $first or $i > $last) {$c .= ' '} else {$c .= '_'}
  if ($i < $first or $i >= $last) {$c .= '       '} else {$c .= '_______'}
 }
 for my $i (0 .. $#spans) {
  #print "$spans[$i]{posL} $spans[$i]{posR} $spans[$i]{overall}\n";
  next unless $spans[$i]{ints};
  $s .= (' ' x ($spans[$i]{posL}*8)) . ('_' x (($spans[$i]{posR}-$spans[$i]{posL})*8)) . " " . sprintf('%.2f', $spans[$i]{logscore}) . "\n";
 }
 $c .= '|' if $cuts{$#segments + 1};
 $l =~ s/[0-9]//g;
 $rej .= "\n" if $rej and $rej !~ /\n$/;
 return "$header\n$ret$n\n$l\n$d\n$p$segments[-1]{R}\n$s$c\n$rej//\n\n";
}

sub MultiT {
 my ($dna, $end, $ret, $extra) = (@_, '|', '');
 return($ret, $extra) unless $ends{$dna}{$end}{trna};
 $ret = join ('', keys %{$ends{$dna}{$end}{trna}});
 $ret =~ s/[\d]//g;
 $extra = "; Other tRNA at $end:$2" if $ret =~ s/^(.)(.+)/$1/;
 #warn "Multi-tRNA at end $dna:$end => $ret (extra $extra)\n" if keys %{$ends{$dna}{$end}{trna}} > 1;
 return($ret, $extra);
}

sub Ends {
 my %i;
 @i{qw/dna id supp L R LL LR RL RR center/} = @_;
 #print "dna=$i{dna} id=$i{id} L=$i{L} R=$i{R} LL=$i{LL} LR=$i{LR} RL=$i{RL} RR=$i{RR} supp=$i{supp}\n";
 my $dna = $i{dna};
 for my $side (qw/L R/) {
  my ($expand, $done);
  $i{$side} = $i{$side.'L'} if $i{$side} < $i{$side.'L'};  # Adjust occasional cases (eg, Tsa1.50D) when end called outside overlap window
  $i{$side} = $i{$side.'R'} if $i{$side} > $i{$side.'R'};
  for (sort {$a <=> $b} keys %{$ends{$dna}}) {
   my $j = $ends{$dna}{$_};
   #die "No $side.L found\n" unless $i{$side.'L'};
   #die "No previous R found\n" unless $$j{R};
   next if $i{$side.'L'} > $$j{R};
   last if $i{$side.'R'} < $$j{L};
   if ($i{$side.'L'} < $$j{L}) {$$j{L} = $i{$side.'L'}; $expand = $_}
   if ($i{$side.'R'} > $$j{R}) {$$j{R} = $i{$side.'R'}; $expand = $_}
   $$j{members}{$i{id}.$side} ++;
   $$j{supp} += $i{supp};
   #print "Fit $i{id}.$side $i{L}-$i{R} into $$j{founder}($$j{L}-$$j{R})\n";
   $i{$side} = $$j{coord};
   $done ++;
  }
  unless ($done) {  # End is new, start new entry
   $endorder ++;
   #warn "new start $i{id}.$side $i{$side} L=$i{$side.'L'} R=$i{$side.'R'}\n";
   %{$ends{$dna}{$i{$side}}} = (L => $i{$side.'L'}, R => $i{$side.'R'}, order => $endorder, nominal => $i{$side}, coord => $i{$side}, founder => $i{id}.$side, members => {$i{id}.$side => 1}, supp => $i{supp});
   $ends{$dna}{$i{$side}}{center} = $i{center} if $i{center} and $i{$side} == $i{center};
   die "$dna: $i{$side} $i{$side.'L'}" unless $ends{$dna}{$i{$side}}{L};
  }
  next unless $expand;  # Otherwise, possible merging
  my $to = $ends{$dna}{$expand};
  #print "testing expansion of $i{$side} by $i{id} $side\n";
  #$i{$side} = $ends{$dna}{$expand}{coord};
  for (sort {$a <=> $b} keys %{$ends{$dna}}) {
   next unless $ends{$dna}{$_};  # May have been deleted after merge
   my $from = $ends{$dna}{$_};
   next if $$to{L} > $$from{R};
   last if $$to{R} < $$from{L};
   next if $$from{coord} eq $expand;  # Skip self
   if ($$from{order} < $$to{order}) {  # Older end is target for merge [What?]
    ($from, $to) = ($to, $from);
    $expand = $$to{coord};
    $i{$side} = $$to{coord};
    #print "switch: from $$from{coord} to $$to{coord}\n";
   }
   for (keys %{$$from{members}}) {
    $$to{members}{$_} ++;
    die "$dna $_ parse\n" unless /(.*)([LR])$/;
    $isl{$dna}{$1}{'end'.$2} = $$to{coord};
    #print "isle $1 $2 changed from $$from{coord} to $$to{coord}\n";
   }
   if ($$from{L} < $$to{L}) {$$to{L} = $$from{L}}
   if ($$from{R} > $$to{R}) {$$to{R} = $$from{R}}
   #print "deleting $dna end $$from{coord}($ends{$dna}{$$from{coord}}{coord})\n";
   delete $ends{$dna}{$$from{coord}};
   #print join(',', sort {$a <=> $b} keys %{$ends{$dna}}), " ends remaining end$side=$i{$side}\n";
  }
  #print "$dna $side $i{id} $i{$side}\n"
 }
 #print "$dna $i{id} $i{L} $i{R}\n";
 return $i{L}, $i{R};
}

sub EndCt {
 my $ct = 0;
 #for my $dna (sort keys %ends) {$ct += scalar keys %{$ends{$dna}}; for (keys %{$ends{$dna}}) {warn "$dna $_ $ends{$dna}{$_}{coord} $ends{$dna}{$_}{supp}\n"}}
 for my $dna (sort keys %ends) {$ct += scalar keys %{$ends{$dna}}}
 warn "$ct ends\n" if $verbose;
}

sub EndTrna {
 for my $dna (sort keys %ends) {
  for my $end (keys %{$ends{$dna}}) {
   for (@{$trnas{$dna}}) {next if $$_{R} < $end; last if $$_{L} > $end; $ends{$dna}{$end}{trna}{$$_{id}} =1}
  }
 }
}

sub Islander {
 warn "Islander input $_[0]\n" if $verbose; 
 for (@{ReadFile($_[0])}) {
  next if /replicon=Plm/;
  chomp;
  my @f = split "\t"; 
  my %l = (dna => $f[0], source => 'Islander',  L => $f[3], R => $f[4], score => $f[5], orient => $f[6], trnaSide => 'L',
   line => $_, f8 => $f[8], reject_type => 'final', supp => 0, rRNA => '');
  for (split ';', $f[8]) {$l{$1} = $2 if /^([^=]+)=([^;]+)/ and not defined $l{$1}}
  my %flag; for (@{$rrna{$f[0]}}) {last if $$_[0] > $f[4]; next if $$_[1] < $f[3]; $flag{$$_[2]} ++}
  print "Rejecting $f[0]:$f[3]-$f[4], rRNA operon\n", next if $flag{'23S'} and $flag{'16S'};
  next if $rejects{$l{ID}};
  next if $l{origin} == 1;  # Deal with origin-crossers later, manually?
  $l{brief} = sprintf('%0.f', ($l{R}-$l{L}+1)/1000) . '.' . $l{tRNA_aa};
  $l{target} = $l{tRNA_aa};
  my ($coord, $dir) = ($l{L}, 1);  # Start calculating tRNA query hit genomic coordinates
  if (abs($l{hitStart} - $l{L}) < abs($l{hitStart} - $l{R})) {$coord = $l{R}; $l{trnaSide} = 'R'}  # Hit closer to L (so tRNA closer to R)
  $dir = -1 if $f[6] eq '-';
  my @ends = ($coord + $dir*($l{qEnd} - $l{int_site}), $coord + $dir*($l{qStart} -$l{int_site}), $l{hitStart}, $l{hitEnd});  # Overlap coords on tRNA
  ($l{OLL}, $l{OLR}, $l{ORL}, $l{ORR}) = sort {$a <=> $b} @ends;
  #for (keys %{$isl{$f[0]}}) {if ($l{L} == $isl{$f[0]}{$_}{L} and $l{R} == $isl{$f[0]}{$_}{R}) {warn "Dupe: $l{dna}:$l{L}-$l{R}\n"; last}}
  warn "$l{ID}: $l{L}, $l{R}: $l{OLL}, $l{OLR}, $l{ORL}, $l{ORR}\n";
  #die "$f[0] $l{ID} $l{hitStart} $l{hitEnd}\n$_\n" unless $l{hitStart} and $l{hitEnd};
  $ct{islct} ++;
  $l{reject} = '';
  @l{qw/endL endR/} = Ends($f[0], $ct{islct}, $l{supp}, (sort {$a <=> $b} $l{L}, $l{R}), $l{OLL}, $l{OLR}, $l{ORL}, $l{ORR}, $l{center});
  #print "$l{ID}: L=$l{L}, R=$l{R}, endL=$l{endL}, endR=$l{endR}, suppL=$ends{$f[0]}{$l{endL}}{supp}, suppR=$ends{$f[0]}{$l{endR}}{supp}, LL=$l{OLL}, LR=$l{OLR}, RL=$l{ORL}, RR=$l{ORR}\n";
  $isl{$f[0]}{$ct{islct}} = \%l;
 }
}

sub FreshTandem {  # Separated from Islander because endL,endR may change during loading
 warn "FreshTandem\n" if $verbose; 
 for my $dna (keys %isl) {
  for my $isle (keys %{$isl{$dna}}) {
   my $i = \%{$isl{$dna}{$isle}};
   @{$i}{qw/len deltaint deltaside ints foreign housekeep hypoth delta_GC dinuc overall logscore/} = Span($dna, $$i{endL}, $$i{endR});
   my $t = \%{$tandems{$dna}{$$i{group}}};
   $$t{sources}{Islander} ++; $$t{members}{$isle} ++;
   $$t{ends}{$$i{endL}} ++; $$t{ends}{$$i{endR}} ++;
   if ($$i{questionable}) {$$t{questionable} = 1} else {$$t{questionable} = 0}
   $$t{bestSupp} = 0; $$t{trnaSide} = $$i{trnaSide}; $$t{id} = 'I' . $$i{group}; $$t{target} = $$i{tRNA_aa}; $$t{orient} = $$i{orient};
   $$t{trnaStepoverTest} = sub {return 1 if shift() < $$i{endL}}; #$ends{$dna}{$tends[0]}{L}};
   $$t{trnaStepoverTest} = sub {return 1 if shift() > $$i{endR}} if $$t{trnaSide} eq 'R';
   $$t{bestScore} = $$i{logscore} unless $$t{bestScore} and $$t{bestScore} < $$i{logscore};
   $$t{project} = $$i{project};
   $$t{dna} = $dna;
  }
  for (keys %{$tandems{$dna}}) {$tandems{$dna}{$_}{power} = scalar(keys %{$tandems{$dna}{$_}{ends}})}
 }
}

sub Tiger {
 warn "TIGER input $_[0]\n" if $verbose;
 for (@{ReadFile($_[0])}) {
  # SHRK01000017.1  TIGER   island  1       23989   148     -       .       ID=Blo220.60.L;brief=60.L;coord=SHRK01000017.1/23989-1+SHRK01000018.1/1-36385;compose=cross;len=60372;context=L;flanks=nudF<>pdtaR;flip=1;bitsum=30981;gnm=Blo292/CP026999.1;crossover=34;int=Y-Int.2:36068-34704;mid=35386;side=R3849;end0=SHRK01000017.1,-1,23972..24005;end1=SHRK01000018.1,-1,36368..36403;OL=23972-24005;OR=36368-36401;OU=841539-841572;mobQ1=;mobQ2=;IS=;ISoverlap=;transposon=;ISidentical=;q1=99.971:1-14018(SHRK01000018.1:50385-36368)>855554-841539;q2=99.856:218-3000>SHRK01000017.1:23972-26754;q1identity=99.971;q2identity=99.856;isleLseq=CTTTGGCACGCCCTCGTATCCCAATTGGTAGAGGAAGCAGCCTCAAAATCtgcgcagtgtgggttcgagtcccaccgagggcacCCAAAAGTCCGGGTCATACGGCATCACGATGGCGCGGGGCGAATTGTTCG;unintSeq=CTTTGGCACGCCCTCGTATCCCAATTGGTAGAGGAAGCAGCCTCAAAATCtgcgcagtgtgggttcgagtcccaccgagggcacTTTAGTTAGGAGTTCGCTGAAATTATTGTGAACCCCATTGTTGGGTAATT;isleRseq=TGAGTCAGAAGCGATTCCTGACAAGGAATTGCCCTCAGCTCGGCAGGGTAtgcgaaggtggtgggttcgagtcccaccgagggcACTTTAGTTAGGAGTTCGCTGAAATTATTGTGAACCCCATTGTTGGGTAA;mean=25095.1397849462;SD=5715.70233239129;deltaint=1;foreign=2.13980503894524;housekeep=2.4576843064147;hypoth=0.578389830508475;delta_GC=0.05835;dinuc=0.076675;islrScore=3.33601552941834e-06;compScore=1.86220330389706e-06;project=genome;division=;phylum=;order=;class=;family=;genus=;species=;org=;taxid=gencode=11;replicon=Scf;qlen=15000;refannot=;ints=Y-Int.2;reject=;positive=true;status=nonoverlap;
  next if /replicon=Plm/;
  chomp;
  my $coord = $1 if /coord=([^;]+);/;
  my @f = split "\t";
  $coord = "$f[0]/$f[3]-$f[4]" unless $coord;
  $f[8] .= "compose=simple;" unless $f[8] =~/compose=[^;]+/;
  my @contig = split(/\+/, $coord);
  my @other;
  my $line = $_;
  for (0..$#contig) {
   next unless $contig[$_] =~ /([^\/]+)\/(\d+)-(\d+)/;
   $f[0] = $1; ($f[3], $f[4]) = sort {$a <=> $b} ($2, $3); $f[6] = ($3 > $2) ? "+" : "-";
   my %flag; for (@{$rrna{$f[0]}}) {last if $$_[0] > $f[4]; next if $$_[1] < $f[3]; $flag{$$_[2]} ++}
   print "Rejecting $f[0]:$f[3]-$f[4], rRNA operon\n", next if $flag{'23S'} and $flag{'16S'};
   my %l = (dna => $f[0], source => 'TIGER', L => $f[3], R => $f[4], supp => $f[5], orient => $f[6], line => $line, f8 => $f[8], rRNA => '', trnaSide => '');
   for (split ';', $f[8]) {$l{$1} = $2 if /^([^=]+)=([^;]+)/}
   die "$_\n" unless $l{R} and $l{L} and $l{brief};
   $serials{$l{brief}} ++;
   $nick = $l{ID} if $nick eq "No_Nick"; $nick =~ /^([^\.]+)/; $nick = $1;
   $l{ID} = "$nick.$l{brief}.$serials{$l{brief}}";
   $l{target} = $l{brief}; $l{target} =~ s/[^\.]+\.//;
   $f[0] =~ /^([^\.]+)/;
   $gnm{bestSupp} = $f[5] unless $gnm{bestSupp} and $gnm{bestSupp} > $f[5];
   next if $rejects{$l{ID}};
   unless ($f[8] =~ /OL=(\d+)-(\d+);OR=(\d+)-(\d+);/) {print "no OL or OR for $_\n"; next}
   my ($LL, $LR, $RL, $RR) = ($1, $2, $3, $4);
   if ($l{compose} eq "simple") {
    ($l{OLL}, $l{OLR}, $l{ORL}, $l{ORR}) = sort {$a <=> $b} ($LL, $LR, $RL, $RR);
   } else {
    if ($_) {
     ($l{ORL}, $l{ORR}) = sort {$a <=> $b} ($RL, $RR);
     ($l{OLL}, $l{OLR}, $l{center}) = ($l{L}, $l{L}, $l{L});
    } else {
     ($l{OLL}, $l{OLR}) = sort {$a <=> $b} ($LL, $LR);
     ($l{ORL}, $l{ORR}, $l{center}) = ($l{R}, $l{R}, $l{R});
    }
   }
   $ct{islct} ++;
   @l{qw/endL endR/} = Ends($l{dna}, $ct{islct}, $l{supp}, $l{L}, $l{R}, $l{OLL}, $l{OLR}, $l{ORL}, $l{ORR}, $l{center});
   #die "$l{ID}: L=$l{L}, R=$l{R}, endL=$l{endL}, endR=$l{endR} LL=$l{OLL}, LR=$l{OLR}, RL=$l{ORL}, RR=$l{ORR} supp=$l{supp}\n";
   $isl{$f[0]}{$ct{islct}} = \%l;
   push @other, ($f[0], $ct{islct});
  }
  next if $f[8] =~ /compose=simple/;
  $isl{$other[0]}{$other[1]}{other} = \%{$isl{$other[2]}{$other[3]}}; $isl{$other[2]}{$other[3]}{other} = \%{$isl{$other[0]}{$other[1]}};
 }
}

sub Foreign {
 my ($dna, $ints, $L, $R, $origin) = @_;
 my ($cds, $hypoth, $pfam, $forn, $hskp) = (0,0,0,0,0);
 for my $prot (@{$stats{$dna}{annots}}) {
  next unless $$prot{type} eq 'CDS';
  if ($$prot{annot} and $$prot{annot} =~ /^[PR]/) {next if $$prot{R} < $L or $$prot{L} > $R} 
  else {
   if ($origin == 1) {next if $$prot{L} <= $L and $$prot{R} >= $R}
   else {next unless $$prot{L} >= $L and $$prot{R} <= $R; last if $$prot{L} > $R}
  }
  $cds ++;  
  if ($$prot{pfam1}) {
   #print "$$prot{pfam1} $$prot{L} $$prot{R}\n";
   $pfam ++;
   $forn += $fornEnrich{$$prot{pfam1}} if $fornEnrich{$$prot{pfam1}};
   $hskp += $hskpEnrich{$$prot{pfam1}} if $hskpEnrich{$$prot{pfam1}};
  } else {$hypoth ++}
 }
 $cds = 1 unless $cds; $pfam = 1 unless $pfam;  # Prevent division by zero
 #print "$L, $R, $cds, $forn, $hskp, $hypoth $stats{$ref}{hypoth} $stats{$ref}{forn} $stats{$ref}{hskp}\n"; 
 $hypoth /= $cds;  $hypoth -= $stats{$dna}{hypoth};
 $forn   /= $pfam; $forn   -= $stats{$dna}{forn};
 $hskp   /= $pfam; $hskp   -= $stats{$dna}{hskp};
 return $hypoth, $forn, $hskp;
}

sub IntOverlap {
 my ($dna, $L, $R) = @_;
 my (@ints, %reserves);  # Reserves in case endpoint shifts all int midpoints outside island
 my %d = (L => 200000, R => 200000, side => '');
 for (keys %{$$intList{$dna}}) {
  my ($Lint, $Rint, $mid) = @{$$intList{$dna}{$_}};
  next if $Rint < $L or $Lint > $R;
  my %delta = (L => $Lint-$L, R => $R-$Rint);
  if ($mid < $L) {$reserves{"L$_:$Lint-$Rint"} = $delta{L}; next}
  if ($mid > $R) {$reserves{"R$_:$Lint-$Rint"} = $delta{R}; next}
  for (qw/L R/) {
   $delta{$_} = 1 if $delta{$_} < 1;
   $d{$_} = $delta{$_} if $delta{$_} < $d{$_}
  }
  push @ints, "$_:$Lint-$Rint";
 }
 $d{best} = $d{L};
 if ($d{L} < $d{R}) {$d{side} = 'L'} elsif ($d{L} > $d{R}) {$d{side} = 'R'; $d{best} = $d{R}} elsif (@ints) {$d{side} = 'LR'}
 return (join(',', @ints), $d{side}, $d{best}) if @ints or keys %reserves == 0;
 $d{best} = (sort {$reserves{$a} <=> $reserves{$b}} keys %reserves)[0];
 $d{best} =~ s/^(.)//; $d{side} = $1;
 return $d{best}, $d{side}, 1;
}

sub IntList {
 my %intList;
 for (`cat genome.gff`) {
  my @f = split "\t";
  push @{$rrna{$f[0]}}, [$f[3], $f[4], $1] if /\trRNA\t.*product=(23S|16S) ribosomal RNA/;
  my $annot;
  if ($logic) {
   next unless $f[8] =~ /annot=(Y-Int|S-Int)/; $annot = $1;
  } else {
   #next if /(?i)transposase/;
   next unless $f[8] =~ /annot=([^;]+)/; $annot = $1;
  }
  @{$intList{$f[0]}{$annot}} = ($f[3], $f[4], int(($f[3]+$f[4])/2));  # Gene midpoint
 }
 return \%intList;
}

sub Bias {
 my ($dna, $L, $R, $origin) = @_;
 #warn "$dna:$L-$R\n";
 my $dnaout = ">$dna:$L-$R\n" . substr($stats{$dna}{seq}, $L-1) . substr($stats{$dna}{seq}, 0, $R);
 #warn length($stats{$dna}{seq}), " $L $R:bias\n";
 #if ($origin == -1) {$dnaout .= substr($stats{$dna}{seq}, $L-1, $R-$L+1)}
 #else {$dnaout .= substr($stats{$dna}{seq}, $L-1) . substr($stats{$dna}{seq}, 0, $R)}
 open DNA, ">test.fa"; print DNA "$dnaout\n"; close DNA;
 my $out = `perl $dir/relAbun.pl test.fa`; chomp $out; $out =~ s/\n.*//s; my @testRA = split "\t", $out;
 my ($delta_GC, $di) = (($testRA[1]-$stats{$dna}{dnaRA}[1])/2, 0);
 for (2,3,4,6,7,9) {$di += abs($testRA[$_]-$stats{$dna}{dnaRA}[$_])}
 $di *= 2; # Double the 6 asymmetrical dinucs above to account for their complements, but don't double the 4 symmetrical dinucs below
 for (5,8,10,11) {$di += abs($testRA[$_]-$stats{$dna}{dnaRA}[$_])}
 return ($delta_GC, $di/16);
}

sub Scores {
 my ($dna, $L, $R, $origin) = @_;
 Load_dna() unless $stats{$dna} and $stats{$dna}{seq};
 #die "$dna $L $R ", length($stats{$dna}{seq}), " bp\n";#, $stats{$dna}{seq}\n";
 my $len = Len($dna, $L, $R);
 die keys(%stats), " $dna $len $L $R $origin\n" if $L < 1 or $R > $stats{$dna}{len} or $L == $R;
 #warn length($stats{$dna}{seq}), " 2 $dna $L $R $origin $stats{$dna}{len}:scores\n" if not $stats{$dna}{len} or $stats{$dna}{len} == length($stats{$dna}{seq}); 
 my ($ints, $deltaside, $delta_int) = IntOverlap($dna, $L, $R);
 my ($deltaGC, $dinuc) = Bias($dna, $L, $R, $origin);  # Use whole genomes stats
 my ($hypoth, $forn, $hskp) = Foreign($dna, $ints, $L, $R, $origin);
 my ($overall, $logscore) = Score($len, $delta_int, $forn, $hskp, $hypoth, $deltaGC, $dinuc);
 return ($len, $delta_int, $deltaside, $ints, $forn, $hskp, $hypoth, $deltaGC, $dinuc, $overall, $logscore);
}

sub Len {
 my ($dna, $L, $R) = @_;
 if ($R < $L) {return $R+$stats{$dna}{len}-$L+1}  # Around-origin
 return $R-$L+1;
}

sub Score {
 my ($len, $delta_int, $forn, $hskp, $hypoth, $deltaGC, $dinuc) = @_;
 my $sco = exp(30.6077118+ -8.2975315*log10($len) + -0.3310587*log10($delta_int) + -3.2087991*$forn + -1.7145020 *$hskp +
  -22.2829392*$hypoth + -16.0497881*log10(abs($deltaGC)+0.01) + -149.2433560*$dinuc); #cutoff=0.51
 #my $sco = exp(30.6077118 + -5.18666237*log10($len) + 0.03581227*log10($delta_int) + -0.90655167*$forn + -0.69860050 *$hskp +
 # -5.87229832*$hypoth + -3.77570683*log10(abs($deltaGC)+0.01) + -36.14100604*$dinuc); #cutoff=0.6209164
 return ($sco, log10($sco)-log10($cutoff));
}

sub log10 {return log(shift)/log(10)}
