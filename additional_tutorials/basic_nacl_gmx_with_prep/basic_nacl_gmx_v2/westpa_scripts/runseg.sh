#!/bin/bash
#
# runseg.sh
#
# WESTPA runs this script for each trajectory segment. WESTPA supplies
# environment variables that are unique to each segment, such as:
#
#   WEST_CURRENT_SEG_DATA_REF: A path to where the current trajectory segment's
#       data will be stored. This will become "WEST_PARENT_DATA_REF" for any
#       child segments that spawn from this segment
#   WEST_PARENT_DATA_REF: A path to a file or directory containing data for the
#       parent segment.
#   WEST_CURRENT_SEG_INITPOINT_TYPE: Specifies whether this segment is starting
#       anew, or if this segment continues from where another segment left off.
#   WEST_RAND16: A random integer
#
# This script has the following three jobs:
#  1. Create a directory for the current trajectory segment, and set up the
#     directory for running gmx mdrun
#  2. Run the dynamics
#  3. Calculate the progress coordinates and return data to WESTPA


# If we are running in debug mode, then output a lot of extra information.
if [ -n "$SEG_DEBUG" ] ; then
  set -x
  env | sort
fi

######################## Set up for running the dynamics #######################

# Set up the directory where data for this segment will be stored.
cd $WEST_SIM_ROOT
mkdir -pv $WEST_CURRENT_SEG_DATA_REF
cd $WEST_CURRENT_SEG_DATA_REF

#copy the script for calculating the progress coordinate 
cp $WEST_SIM_ROOT/bstate/pcoord.py $WEST_CURRENT_SEG_DATA_REF/

# Make a symbolic link to the topology file. This is not unique to each segment.
ln -sv $WEST_SIM_ROOT/common_files/nacl.top .
ln -sv $WEST_SIM_ROOT/common_files/tip3p_ionsjc2008.ff .

# Either continue an existing tractory, or start a new trajectory. Here, both
# cases are the same.  If you need to handle the cases separately, you can
# check the value of the environment variable "WEST_CURRENT_SEG_INIT_POINT",
# which is equal to either "SEG_INITPOINT_CONTINUES" or "SEG_INITPOINT_NEWTRAJ"
# for continuations of previous segments and new trajectories, respecitvely.
# For an example, see the nacl_amb tutorial.

# The weighted ensemble algorithm requires that dynamics are stochastic.
# We'll use the "sed" command to replace the string "RAND" with a randomly
# generated seed.
sed "s/RAND/$WEST_RAND16/g" $WEST_SIM_ROOT/common_files/md.mdp > md.mdp

# This trajectory segment will start off where its parent segment left off.
# The "ln" command makes symbolic links to the parent segment's edr, gro, and 
# and trr files. This is preferable to copying the files, since it doesn't
# require writing all the data again.
if [ "$WEST_CURRENT_SEG_INITPOINT_TYPE" = "SEG_INITPOINT_CONTINUES" ]; then
  ln -sv $WEST_PARENT_DATA_REF/seg.edr ./parent.edr
  ln -sv $WEST_PARENT_DATA_REF/seg.gro ./parent.gro
  ln -sv $WEST_PARENT_DATA_REF/seg.trr ./parent.trr

elif [ "$WEST_CURRENT_SEG_INITPOINT_TYPE" = "SEG_INITPOINT_NEWTRAJ" ]; then
#  sed "s/RAND/$WEST_RAND16/g" $WEST_SIM_ROOT/common_files/md.in > md.in
  ln -sv $WEST_SIM_ROOT/bstates/bstate.edr ./parent.edr
  ln -sv $WEST_SIM_ROOT/bstates/bstate.gro ./parent.gro
  ln -sv $WEST_SIM_ROOT/bstates/bstate.trr ./parent.trr
fi
echo "howdy"

# Run the GROMACS preprocessor 
$GMX grompp -f md.mdp -c parent.gro -e parent.edr -p nacl.top \
  -t parent.trr -o seg.tpr -po md_out.mdp

############################## Run the dynamics ################################
# Propagate the segment using gmx mdrun
$GMX mdrun -s   seg.tpr -o seg.trr -c  seg.gro -e seg.edr \
  -cpo seg.cpt -g seg.log -nt 1

########################## Calculate and return data ###########################

# Calculate the progress coordinate
python3 $WEST_SIM_ROOT/bstates/pcoord.py $WEST_CURRENT_SEG_DATA_REF/seg.trr $WEST_CURRENT_SEG_DATA_REF/seg.gro
cat $WEST_CURRENT_SEG_DATA_REF/pcoord.txt | awk '{print $1;}' > $WEST_PCOORD_RETURN 
rm $WEST_CURRENT_SEG_DATA_REF/pcoord.txt

cp nacl.top $WEST_TRAJECTORY_RETURN
cp seg.gro $WEST_TRAJECTORY_RETURN
cp seg.trr $WEST_TRAJECTORY_RETURN
cp seg.edr $WEST_TRAJECTORY_RETURN

cp nacl.top $WEST_RESTART_RETURN
cp seg.gro $WEST_RESTART_RETURN/parent.gro
cp seg.trr $WEST_RESTART_RETURN/parent.trr
cp seg.edr $WEST_RESTART_RETURN/parent.edr

cp seg.log $WEST_LOG_RETURN

# Clean up all the files that we don't need to save.
rm -f dist.xvg md.mdp md_out.mdp nacl.top  parent.trr seg.cpt seg.pdb seg.tpr parent.edr
rm -r tip3p_ionsjc2008.ff
