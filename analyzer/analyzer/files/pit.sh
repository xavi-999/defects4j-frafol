#!/bin/bash

HERE=$(dirname "$0")
# suppose we are in base/work/<repo>
# BASE=$(cd $HERE/../.. && pwd)
BASE=$(cd $(dirname $(which defects4j))/../.. && pwd)

MUTATION_TOOLS=$(cd $BASE/mutation_tools && pwd)
LIB_HOME="$MUTATION_TOOLS/lib"
PIT_HOME="$MUTATION_TOOLS/pitest-1.15.2-jars"

PIT_VERSION="1.17.0"
PITEST_JUNIT_PLUGIN_VERSION="1.2.1"
JUNIT_JUPITER_VERSION="5.9.2"
JUNIT_PLATFORM_VERSION="1.9.2"

JUNIT="$PIT_HOME/junit-4.12.jar"
JUNIT_PLATFORM="$PIT_HOME/junit-platform-console-standalone-$JUNIT_PLATFORM_VERSION.jar"  # JUnit 5 Platform
PITEST="$PIT_HOME/pitest-$PIT_VERSION.jar"
PITEST_ENTRY="$PIT_HOME/pitest-entry-$PIT_VERSION.jar"
PITEST_CLI="$PIT_HOME/pitest-command-line-$PIT_VERSION.jar"
PITEST_JUNIT5_PLUGIN="$PIT_HOME/pitest-junit5-plugin-$PITEST_JUNIT_PLUGIN_VERSION.jar"  # PIT JUnit 5 Plugin

JUNIT_JUPITER_API_JAR="$PIT_HOME/junit-jupiter-api-$JUNIT_JUPITER_VERSION.jar"
JUNIT_JUPITER_ENGINE_JAR="$PIT_HOME/junit-jupiter-engine-$JUNIT_JUPITER_VERSION.jar"
JUNIT_VINTAGE_ENGINE_JAR="$PIT_HOME/junit-vintage-engine-$JUNIT_JUPITER_VERSION.jar"
    

CP="$PITEST_JUNIT5_PLUGIN:$PITEST:$PITEST_ENTRY:$PITEST_CLI"

echo "Base is           : $BASE"
echo "Mutation tools is : $MUTATION_TOOLS"
echo "PIT home is       : $PIT_HOME"
echo

TARGET=$HERE/target
CLS=$TARGET/classes

# take every folder "test*" like (ignore case)
TST=$(cd $(find $TARGET -iname "test*" -type d) && pwd || exit)

if [ "$TST" == "$HOME" ]; then
  echo "TEST DIR not found!" && exit
fi

PIT_CMD="org.pitest.mutationtest.commandline.MutationCoverageReport"
CLS_FLAG="--classPath $CLS,$TST"
CP="$CP:$CLS:$TST"

TEST_TARGET="<TEST_REGEXP>"
CLASS_TARGET="<CLASS_REGEXP>"
TARGET_FLAG="--targetClasses $CLASS_TARGET --targetTests $TEST_TARGET"

REPORT="--reportDir $HERE/pit_report"
TIMESTAMPED_REPORTS="--timestampedReports false"
SRC="--sourceDirs $HERE/src/main/java"

DEFAULTS="--mutators DEFAULTS"
STRONGER="--mutators STRONGER"
ALL="--mutators ALL"
MUTATORS=$STRONGER

OUTPUT_FORMATS="--outputFormats html,xml,csv"

CMD="java -cp $CP $PIT_CMD $TARGET_FLAG $REPORT $SRC $MUTATORS $OUTPUT_FORMATS $TIMESTAMPED_REPORTS --verbose --skipFailingTests"

echo "Command to run:"
echo $CMD 
echo
$CMD
