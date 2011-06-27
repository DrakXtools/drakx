package check_min_sys_requirements;

use strict;
use warnings;
use common;
use utf8;

my $min_sys_conf_file = '/etc/minsysreqs';

sub total_mem_size() {
  my $parameter;
  my $size;
  my $unit;

  open(mem_info, '/proc/meminfo');
    while (<mem_info>) {
	($parameter, $size, $unit) = split();
	if ($parameter eq "MemTotal:") {
	    if ($unit eq "kB") {
		$size = $size/1024;
		}
    	    return int($size);
        }
    }
}

sub total_hdds_size {
    my @output = `fdisk -l| grep "/dev/sd.:\\|/dev/hd.:"`;
    my $hdds;
    my $rounded;
    my $str;

    foreach $str (@output) {
        my @list = split(/ /,$str);
        $hdds += $list[4]/(1000**3);
        $rounded = sprintf("%.1f",$list[4]/(1000**3)); 
        $_[0] .= "  HDD ".$list[1]." ".$rounded." Gb\n",;
    }

    return  $hdds;
}

sub min_system_requirements {
    my $parameter;
    my $size;
    open(min_info, $min_sys_conf_file) or die("Cannot open file ".$min_sys_conf_file);
    while (<min_info>) {
       chomp();
       ($parameter, $size) = split(/[ \t]*=[ \t]*/);
	 if (defined($parameter)) {
            if ($parameter eq "ram") {
               $_[0]= $size;
            }
            if ($parameter eq "hdd") {
               $_[1]= $size;
            }
         }
    }
}    


sub check_min_sys_requirements {
    my ($in) = @_;
    my $total_ram;
    my $total_hdds;
    my $warning;
    my $hdd_message;
    my $min_mem;
    my $min_hdd;
    my $sys_failed;

    $sys_failed = 0;

    min_system_requirements($min_mem, $min_hdd);
    $total_ram = total_mem_size();
    $total_hdds = total_hdds_size($hdd_message);
    
    $warning .= N("System requirements warning\n");
    $warning .= N("Recommended system parameters:\n");
    $warning .= N("  RAM = ").$min_mem.N(" Mb\n");
    $warning .= N("  HDD = ").$min_hdd.N(" Gb\n");
    $warning .= N("\nYour system parameters:\n");

    if ($total_ram < $min_mem) {
	$warning .= N("  RAM = ").$total_ram.N(" Mb\n");
       $sys_failed = 1;
    } 
    if ($total_hdds < $min_hdd) {
        $warning.=$hdd_message;
        $sys_failed = 1;
    }

    $warning .= N("\nYour system resources are too low\n");

    my $ok;
    $ok = 1;

    if ($sys_failed) {
        $ok &&= $in->ask_okcancel(N("System requirements warning"), $warning);
    }
   return $ok; 
}


sub main {
   my ($o) = @_;
   check_min_sys_requirements($o);
 
}
