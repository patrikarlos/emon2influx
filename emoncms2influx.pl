#!/usr/bin/perl

use LWP::Simple; 
use Time::HiRes qw(usleep gettimeofday time tv_interval );
use Sys::Hostname;
use JSON; 
use Data::Dumper;
use WWW::Curl::Easy;
use Switch;

do "emoncms2influx.conf";

## Misc Variables
## If enabled; used data after ":" in feed string as key, otherwise it uses data before ":" as key.
## Handy when debugging
$translate=0; 
#Inter probe time; PI/TX should report every 2s, so probe here every n*2, n>1.
$sleepTime=4;

$emoncms = shift or die "Usage: $0 EMONIP.\n";

my %scaleFactors = (
    'tx1_power1' => 8,
    'tx1_power2' => 8,
    'tx1_power3' => 8,
    'tx1_power4' => 8,
    'tx2_power1' => 8,
    'tx2_power2' => 8,
    'tx2_power3' => 8,
    'tx2_power4' => 8,
    'tx3_power1' => 10,
    'tx3_power2' => 10,
    'tx3_power3' => 10,
    'tx3_power4' => 8,
    'tx4_power1' => 10,
    'tx4_power2' => 10,
    'tx4_power3' => 10,
    'tx4_power4' => 8,
    'txP_power1' => 10,
    'txP_power2' => 10,
    'pi1_power1' => 5,
    'pi1_power2' => 5
);


print time(). " Initializing, first piProbe.\n";
#Grab initial copy.
%hashTwo=probePi($apireadkey,3);
print time(). " Initializing, got data, sleeping 5 s.\n";
sleep(5);
    
while(true) {
    $startTime=time();
    print time(). " Probing \n";
    %hashOne=probePi($apireadkey,3);
    my @theKeys = keys %hashOne;
    my @problemString;
    my $problemOEM=" ";
    my $updOEM=" ";

    my $item=0;
    $ts=time();
    #Identify updated Nodes, by checking tsample. 
 #   print "....................................\n";
 #   print "Checking time \n";
    foreach my $key (@theKeys) {
#	print "[" . $key . "] = " . $hashOne{$key} . " ";
	if ($key =~ m/tsample/i) {
#	    print "tsample.\n";
	    ($oemid,$junk)=split(/_/,$key);
#	    print " EmonTX/Pi id = $oemid \n";
	    if ( $hashTwo{$key} < $hashOne{$key} ){
#		print " OK with $key \n";
		$updOEM.=" $oemid";
	    } else {
#		print "Problems with [" . $key .  "] " . $hashOne{$key} . " " . $hashTwo{$key} . "\n";
#		print $hashTwo{$key} . " <=  ". $hashOne{$key} . "\n";
		$problemOEM.=" $oemid"; 
	    }
	} #else {
	  #  print "other (dont care right now) .\n";
	#}
    }
    print time() . "These were updated; $updOEM . ";
    print "These were not; $problemOEM .\n";

    #Now extract the interesting once.
    my $outNstime=time()*1000*1000*1000;
    foreach my $key (@theKeys) {
#	print "[" . $key . "] = " . $hashOne{$key} . "\n";
	if ($key =~ m/power/i) {
	    #	print "power.\n";
	    my $nodeid=0;
	    $nodeid=$key;
	    ($dataA,$dataB)=split(/:/,$key);
	    my $theScale=10; # Default
	    $theScale=$scaleFactors{$dataA};
	    if (!$theScale){
		$theScale=10; # Default
	    }
	    
	    if($translate){
		$keySTR=$dataB;
	    } else {
		$keySTR=$dataA;
	    }
	    ($oemid,$junk)=split(/_/,$key);
	    if ( index($updOEM,$oemid) != -1 ) {
#		print "This OEM has been updated; \n";
#		print "key = $key  => $nodeid \n";

		print time() . " $dataA | $dataB scale = $theScale .\n";
		
		if($hashOne{$key}>0) {
		    push @problemString, "$INFLUXMEAS,node=". $keySTR." value=".($hashOne{$key}/$theScale). "\n";
		} else {
		    push @problemString ,"$INFLUXMEAS,node=". $keySTR." value=".(-1*$hashOne{$key}/$theScale). "\n";
		}
	    } else {
#		print "this did not match, the updated stuff.\n";
	    }
	} 
    }
    pushInflux(\@problemString);
    
    %hashTwo=%hashOne;
    $stopTime=time();
    $mySleep=$sleepTime-($stopTime-$startTime);
    if ($mySleep< 0) {
	$mySleep=2;
    }
    print time() . " Done, sleeping $mySleep s.\n";
    sleep($mySleep);
}


sub pushInflux {
    my @data=@{$_[0]};
#    print "Got this: \n@data \n";
    
    my $outString=join("",@data);
    my $outS=join(",",@data);
    $outS =~ tr{\n}{ };
#    $outString =~ s/\n/ /g;
    
    print "outString = >$outS \n";
#    print "outString (sending) = > $outString \n";
    
    my $curl = WWW::Curl::Easy->new;
    $curl->setopt(CURLOPT_URL, "http://$INFLUXHOST:$INFLUXPORT/write?db=$INFLUXDB");
    $curl->setopt(CURLOPT_USERNAME, $INFLUXUSER);
    $curl->setopt(CURLOPT_PASSWORD, $INFLUXPASSWD);
    my $response_body;
    $curl->setopt(CURLOPT_WRITEDATA,\$response_body);
    $curl->setopt(CURLOPT_POSTFIELDS,$outString);
    

    my $retcode = $curl->perform();
    
    if ($retcode == 0) {
#        print("Transfer went ok\n");
        my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
        # judge result and next action based on $response_code
#        print("Received response: $response_body\n");
    } else {
        # Error code, type of error, error message
        print("An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n");
    }

    return $retcode;
}





sub probePi {
    my $apireadkey=$_[0];
    my $uri=sprintf("http://$emoncms/emoncms/feed/list.json?userid=1&apikey=%s",$apireadkey);
    my $jSonString= get $uri;
    my $json=sprintf("{\"data\": %s}",$jSonString);
    my $decoded=decode_json($json);
    my @friends = @{ $decoded->{'data'} };
    my (%theHash, $key,$val);
    foreach my $f ( @friends ) {
	$key=$f->{"name"};
	$val=$f->{"value"};
	$theHash{$key} = $val;
    }
    return %theHash;
}
