for (`cat isles.fa`) {
 if (/>([^\s\|\+\']+)/) {#close OUT; 
  my $nick = $1;
  my $head = substr($nick, 0, 18);
 system ("mkdir Isles/$nick"); 
 open OUT, ">Isles/$nick/genome.fa"}
 print OUT $_;
}
