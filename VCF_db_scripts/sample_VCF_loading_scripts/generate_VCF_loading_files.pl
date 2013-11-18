#!/usr/bin/perl

## This is the VCF shredder
## It takes a VCF file as input and create several text files to be loaded into tranSMART
## Note: The parsing part should be modified based on the pattern in your VCF file to get the correct data
## The assocaited test files are meant to show a simple example for test purpose only

## The following parameters were used as a test.  Now they are set as commandline arguments. ***
# our $vcf_input = "54genomes_chr17_10genes.vcf";
# our $datasource = "CGI";
# our $dataset_id = "54GenomesChr17";
# our $ETL_user = "HW";
### *****************

if ($#ARGV < 3) {
	print "Usage: perl generate_VCF_loading_files.pl vcf_input_file datasource dataset_id ETL_user\n";
	print "Example: perl generate_VCF_loading_files.pl 54genomes_chr17_10genes.vcf CGI 54GenomesChr17 HW\n\n";
	exit;
} else {
	our $vcf_input = $ARGV[0]; 
 	our $datasource = $ARGV[1];
 	our $dataset_id = $ARGV[2];
 	our $ETL_user = $ARGV[3];
}


## Do Not change anything after this line
our $genome = "hg19";
our $hg_genome = '19';

our (@t, $rs, $clinsig, $disease, %list);

# Save the SNPs with Clinical significance and disease association information 
# Downloaded and re-processed by Haiguo Wu, Recombinant By Deloitte

open IN, "< hg19_snp137_clinsig_disease.txt" or die "Cannot open file: $!";
while (<IN>) {
chomp;
	next if (/^CHR/);
	@t = split(/\t/);
	$rs = $t[2];
	$clinsig = $t[12];
	$disease = $t[13];

	next if ($clinsig eq "" && $disease eq "");
	$list{$rs} = [$clinsig, $disease];

}
close IN;

our $ETL_date = `date +FORMAT=%d-%b-%Y`;
$ETL_date =~ s/FORMAT=//;
$ETL_date =~ s/\n//;
our $depth_threshhold = 10;
our $comment_file = "vcf.header";

open META, "> load_metadata.txt" or die "Cannot open file: $!";
print META "$dataset_id\t$datasource\t$ETL_user\t$ETL_date\t$genome\t$comment_file\n";
close META;

open IN, "< $vcf_input" or die "Cannot open file: $!";
open HEADER, "> $comment_file" or die "Cannot open file: $!";
open IDX, "> load_variant_subject_idx.txt" or die "Cannot open file: $!";
open DETAIL, "> load_variant_subject_detail.txt" or die "Cannot open file: $!";
open SUMMARY, "> load_variant_subject_summary.txt" or die "Cannot open file: $!";
open SI, "> load_variant_rc_snp_info.txt" or die "Cannot open file: $!";
# open TEMP1, "> temp1";
# open TEMP2, "> temp2";

resetNext();

our ($aaChange,$codonChange,$effect,$exonID,$class,$biotype,$gene,$impact,$transcriptID);
our $syn = 0;
our $intron = 0;
our ($chr, $pos, $rs, $ref, $alt, $qual, $filter, $info, $format, @samples);

while (<IN>) {
chomp;
	if (/^##/) {
		print HEADER "$_\n";
		next;
	}
	
	/SNPEFF_AMINO_ACID_CHANGE=(\w\/\w)\;/ and do {
		$aaChange = $1;
	};
	/SNPEFF_AMINO_ACID_CHANGE=(\w\/\*)\;/ and do {
		$aaChange = $1;
	};
	/SNPEFF_AMINO_ACID_CHANGE=(\*\/\w)\;/ and do {
                $aaChange = $1;
        };
	/SNPEFF_CODON_CHANGE=(\w\w\w\/\w\w\w)\;/ and do {
		$codonChange = $1;
	};
	/SNPEFF_EFFECT=(\w+)\;/ and do {
                $effect = $1;
        };
	/SNPEFF_EXON_ID=(\w+)\;/ and do {
		$exonID = $1;
	};
	/SNPEFF_FUNCTIONAL_CLASS=(\w+)\;/ and do {
		$class = $1;
	};
	/SNPEFF_GENE_BIOTYPE=(\w+)\;/ and do {
		$biotype = $1;
	};
	/SNPEFF_GENE_NAME=(\w+)\;/ and do {
		$gene = $1;
	};

	/\|XR_\d+\.\d+\|(\w+)\|/ and do {
		$gene = $1;
	};
	/\|NM_\d+\.\d+\|(\w+)\|/ and do {
                $gene = $1;
        };

	/SNPEFF_IMPACT=(\w+)\;/ and do {
		$impact = $1;
	};
	/SNPEFF_TRANSCRIPT_ID=(\w+)\;/ and do {
		$transcriptID = "";
	};

	if ($effect eq "SYNONYMOUS_CODING") {
		$syn++;
		#resetNext();
		#next;
	}
	if ($effect eq "INTRON") {
		$intron++;
		#resetNext();
		#next;
	}

	($chr, $pos, $rs, $ref, $alt, $qual, $filter, $info, $format, @samples) = split (/\t/);

	if ($pos eq "POS") {
		for ($i = 0; $i <= $#samples; $i++) {
			$subj = $samples[$i];
			$j = $i + 1;
			print IDX "$dataset_id\t$subj\t$j\n";
			push @subjects, $subj;
		}
		print HEADER "$_\n";
		next;
	}

	## Some chromosome positions are mapped to multiple RS IDs which is OK
	## However, if a chromosme position is mapped to multiple unknown RS IDs (.), we have to exclude the repeating lines

	$location = $chr . ":" . $pos;
	if (defined $rs_saved{$location} ) {
		if ($rs eq "." && $rs_saved{$location} eq ".") {

			# print TEMP1 "$chr\t$pos\t$rs_saved{$location}\t$filter\t$rs\n";
			resetNext();
			next;
		} 
	}
	print DETAIL join("<EOF>", $dataset_id, $chr, $pos, $rs, $ref, $alt, $qual, $filter, $info, $format),"<EOF><startlob>", join("\t", @samples), "<endlob><EOF>", "\n";

	if (defined $list{$rs} ) {
		$clinsig =  $list{$rs}[0];
		$disease =  $list{$rs}[1];
	} else {
		$clinsig = "";
		$disease = "";
	}

	if (length($ref) == 1 && length($alt) == 1) {
		$variant_type = "SNV";
	} else {
		$variant_type = "DIV";
	}

	unless ($rs eq ".") {
		print SI join("\t",$rs, $ref,$alt,$gene,$geneID,$hg_version,$variant_type,$strand,$clinsig,$disease,$maf,$biotype,$impact,$transcriptID,$class,$effect,$exonID,$aaChange,$codonChange), "\n";
	}

	for ($i = 0; $i <= $#samples; $i++) {
	  unless ($samples[$i] =~ /\.\/\./ or $samples[$i] =~ /\.\,\./) {
	     # ($gt,$ad,$depth,$gq,$pl) = split (/\:/, $samples[$i]);
	     ($gt,$depth,$ad) = split (/\:/, $samples[$i]);
	     ($a, $b) = split (/\,/, $ad);
	     $diff = abs ($a + $b - $depth);

	    unless ($depth eq "." or $gt =~ /\./) {
	     if ($depth >= $depth_threshhold) {
		if ($gt eq "0/0") {
			$refCount++;
		} elsif ($gt eq "1/1") {
                	$altCount++;
			$variant = $alt . "/" . $alt;
			$variant_format = "V/V";
			print SUMMARY join("\t", $chr, $pos, $dataset_id, $subjects[$i], $rs, $variant, $variant_format,$variant_type),"\n";
		} elsif ($gt eq "0/1") {
			$variant = $ref . "/" . $alt;
			$variant_format = "R/V";
			if ( $a >= $depth_threshhold && $b >= $depth_threshhold) {
			  if ($chr eq "Y") {  ## Higher standard since we do not really expect any Heterologous SNP for Y chromosome
			   $pct_a = $a / $depth;
			   $pct_b = $b / $depth;
			   if ($depth > 20 && $pct_a > 0.35 && $pct_b > 0.35) {
#				print TEMP2 join("\t", $chr, $pos, $dataset_id, $subjects[$i], $rs, $variant, $variant_format,$variant_type),"\n";
			   }
			  } else {
			   print SUMMARY join("\t", $chr, $pos, $dataset_id, $subjects[$i], $rs, $variant, $variant_format,$variant_type),"\n";
			   $het++;
			  }
			}
		} elsif ($gt eq "1/0") {
			$variant =  $alt . "/" . $ref;
			$variant_format = "V/R";
			if ( $a >= $depth_threshhold && $b >= $depth_threshhold) {
                          if ($chr eq "Y") {  ## Higher standard since we do not really expect any Heterologous SNP for Y chromosome
                           $pct_b = $b / $depth;
                           if ($depth > 20 && $pct_a > 0.35 && $pct_b > 0.35) {
#                               print TEMP2 join("\t", $chr, $pos, $dataset_id, $subjects[$i], $rs, $variant, $variant_format,$variant_type),"\n";
                           }
                          } else {
                           print SUMMARY join("\t", $chr, $pos, $dataset_id, $subjects[$i], $rs, $variant, $variant_format,$variant_type),"\n";
                           $het++;
                          }
                        }
		} else {
			print "$chr\t$pos\t$gt\n";
		}
	      }
	    }
          } # end of unless ($samples[$i] ...)
	 } # end of FOR loop for ($i = 0; $i <= $#samples; $i++)

	$rs_saved{$location} = $rs;
	resetNext();
}
close IN;
close OUT;

# print "0/0 ref count: $refCount\n";
# print "1/1 alt count: $altCount\n";
# print "0/1 or 1/0 count: $het\n";
# print "Synonymous coding change: $syn\n";
# print "Within intron: $intron\n";
# print "Low depth of coverage: $lowDepth\n";

sub resetNext {
        $effect = "";
        $gt = "";
	$gene = "";
	$geneID = "";
	$strand = "";
	$maf = "";
	$chr = "";
	$pos = "";
	$rs = "";
	$ref = "";
	$alt = "";
	$variant = "";
	$variant_format = "";
	$class = "";
	$biotype = "";
	$impact = "";
	$depth = "";
	$transcriptID = "";
	$exonID = "";
	$aaChange = "";
	$codonChange = "";
}	


open RUN, "> load_VCF_files.sh" or die "Cannot open file: $!";
print RUN "
date

 sqlldr deapp/deapp control=load_metadata.ctl

date
 sqlldr deapp/deapp control=load_variant_subject_idx.ctl

date
 sqlldr deapp/deapp control=load_variant_subject_summary.ctl ROWS=1000 errors=2000

date
 sqlldr deapp/deapp control=load_variant_subject_detail.ctl errors=2000

date
 sqlldr deapp/deapp control=load_variant_rc_snp_info.ctl ROWS=1000 errors=2000

date
\n";

system "chmod 755 load_VCF_files.sh";


