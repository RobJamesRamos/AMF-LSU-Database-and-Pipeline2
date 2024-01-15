#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=8gb
#SBATCH --time=00-24:00:00
#SBATCH --output=./slurmOutputs/buildTree.%a.out
#SBATCH --error=./slurmOutputs/buildTree.%a.out
#SBATCH --job-name=AMFbuildTree
#SBATCH --array=1-11

echo "debug1"
nSeqsPerSubset=15 # divide the input fasta into subsets with this number of sequences ?
ASV_REPSEQ_FILE="./BLAST_ASVrepseqs_clean_aligned.fasta" # representative sequences of filtered 97% ASVs (generated by AMFtrimmedToASVs.sh), aligned to ref db
STATIC_FILE="./V15_LSUDB_3.23.21_cut_aligned.fasta" # reference sequence database
echo "debug2"
nRepSeqs=`grep -c '>' $ASV_REPSEQ_FILE`  # how many ASV representative sequences are there?
nSubsets=$(($nRepSeqs/$nSeqsPerSubset)) # how many subsets will we need?
# because it automatically rounds down, this gave us the number of FULL subsets. 
# check whether $nRepSeqs divided evenly by $nSeqsPerSubset; if not, add 1 subset
if [ $(($nRepSeqs%$nSeqsPerSubset)) == 0 ]
then
    echo "ASV rep seqs divided evenly into "$nSubsets" subsets of "$nSeqsPerSubset" sequences"
else
    remainder=$(($nRepSeqs%$nSeqsPerSubset)) # store the remainder for future use
    echo "ASV rep seqs divide into "$nSubsets" subsets of "$nSeqsPerSubset" sequences, plus an extra subset of "$remainder" sequences"
    ((nSubsets=nSubsets+1)) # increase the total number of subsets by 1
fi
echo "debug3"

echo "Total number of subsets to cover is $nSubsets"
echo "Slurm array task max is $SLURM_ARRAY_TASK_MAX"

# Debugging lines to make sure the script will cover all the ASV sequences:
### NOTE these were not working - suspect there is a hidden non-integer value of $nSubsets?
#if [ nSubsets != $SLURM_ARRAY_TASK_MAX ]
#then
#    echo "*** ERROR *** number of sequence subsets does not match maximum array value"
#    scancel $SLURM_ARRAY_JOB_ID # cancel the job if this error happens
#fi

echo "debug4"

#Clear Environment
module purge

#Preprocessing of fasta file to split into # of sequences
nLinesPerSubset=$(($nSeqsPerSubset*2))

echo "debug5"

# define how many lines of the input file to read for each subset
# START=$SLURM_ARRAY_TASK_ID
STOP=$((SLURM_ARRAY_TASK_ID*nLinesPerSubset)) # defines last line to read for each subset (each SLURM_ARRAY_TASK_ID = one subset)
START=$(($STOP - $(($nLinesPerSubset - 1)))) # defines what line number to start reading at 
# example, for the first subset (SLURM_ARRAY_TASK_ID==1) will read lines 1-29 when nLinesPerSubset==30 (i.e. nSeqsPerSubset=15)

echo "debug6"
echo "START=$START"
echo "STOP=$STOP"

# Make temporary files to store subsets + intermediate files
TMP_SPLIT_SEQ=$(mktemp)
TMP_SEQ=$(mktemp)
TMP_QZA=$(mktemp --suffix=.qza)
TMP_QZA_ALIGNED=$(mktemp --suffix=.qza)
TMP_OUT_FASTA=$(mktemp -d)

echo "debug7"

# Start reading the ASV representative sequences file, creating subsets of lines $START to $STOP
for (( N = $START; N <= $STOP; N++ )); do
    sed -n "$N"p $ASV_REPSEQ_FILE >> $TMP_SPLIT_SEQ
done

echo "debug8"

#Cat together the split sequence file with static file
cat $TMP_SPLIT_SEQ $STATIC_FILE > $TMP_SEQ

echo "debug9"

#Created new sequence file, don't need this one
rm $TMP_SPLIT_SEQ

echo "debug10"

#3 - Build tree

module load gcc/8.2.0 openmpi/4.0.2 raxml/8.2.12

echo "debug14"

RAxMLoutpath=`pwd`/RAxMLfiles/ # specify FULL path to hold RAxML output files. 

#Input is output of exported fasta file. The output file is uniquely named for the sub sample number
raxmlHPC-PTHREADS-AVX -f d -m GTRGAMMA -p 1723 -N 100 -r Root_V15_LSUDB-1000BS-GTRGAMMA-bootstrap-tree.newick -s $TMP_SEQ -n ${SLURM_ARRAY_TASK_ID}_AMFtree.ENVbackbone -T 16 -w $RAxMLoutpath

#Clean Up
rm -v $TMP_SEQ $TMP_QZA $TMP_QZA_ALIGNED
mv RAxML_* ./RAxMLfiles/
