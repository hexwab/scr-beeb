#!/usr/bin/perl -w
use Digest::CRC qw[crc];
print "UEF File!\x00\x01\x00";
chunk(0x110,pack"v",100); # carrier
undef $/;
open F, "boottape" or die $!;
$data=<F>;
$fn="Stunt Car";
$load=0xffff0500;
$exec=0xffff0506;
$blkno=0;
$blklen=length$data;
$flags=0x81;
my $header=$fn.pack"CVVvvCV",0,
    $load,$exec,$blkno,$blklen,$flags,0xe28ce1;
$header='*'.$header.pack"n",crc($header,16,0,0,0,0x1021,0,0);

$data.=pack"n",crc($data,16,0,0,0,0x1021,0,0);
#print $data;
chunk(0x100,$header.$data);

chunk(0x110,pack"v",220); # carrier
$raw="\xf7\xf7\xf7";
open F, "exodecr" or die $!;
$raw .= reverse <F>;

#file("title.exo");
file("mode7splash.exo");
file("loader2.exo");
file("gfxearly.exo");
file("core.exo");
#file("beebgfx.exo");
#file("beebgfx.exo");
file("kernel.exo");
file("cart.exo");
file("beebmus.exo");
file("gfxlate.exo");
file("hazel.exo");
file("data.exo");
file("data.exo");
chunk(0x100,$raw);

sub file {
    my $fn=shift;
    open F, "<$fn" or die "$fn: $!";
    $raw.=<F>;
}

sub chunk {
    my ($id,$data)=@_;
    print pack"vV",$id,length$data;
    print $data;
}
