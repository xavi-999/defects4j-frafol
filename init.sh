#!/usr/bin/env bash
#
# Exit the shell script immediately if any of the subsequent commands fails.
# immediately
set -e
#

# TODO: Major and the coverage tools should be moved to framework/lib
################################################################################
# This script initializes Defects4J. In particular, it downloads and sets up:
# - the project's version control repositories
# - the Major mutation framework
# - the supported test generation tools
# - the supported code coverage tools (TODO)
################################################################################

HOST_URL="https://defects4j.org/downloads"

# Directories for project repositories and external libraries
BASE="$(cd "$(dirname "$0")"; pwd)"
DIR_REPOS="$BASE/project_repos"
DIR_LIB_GEN="$BASE/framework/lib/test_generation/generation"
DIR_LIB_RT="$BASE/framework/lib/test_generation/runtime"
DIR_LIB_GRADLE="$BASE/framework/lib/build_systems/gradle"

################################################################################

main() {
    echo "Checking system configuration ... "
    # Check whether wget is available on OSX
    if [ "$(uname)" = "Darwin" ] ; then
        if ! wget --version > /dev/null 2>&1; then
            print_error_and_exit "Couldn't find wget to download dependencies. Please install wget and re-run this script."
        fi
    fi
    
    # Check whether curl is available
    if ! curl --version > /dev/null 2>&1; then
        print_error_and_exit "Couldn't find curl to download dependencies. Please install curl and re-run this script."
    fi
    
    # Check whether unzip is available
    if ! unzip -v > /dev/null 2>&1; then
        print_error_and_exit "Couldn't find unzip to extract dependencies. Please install unzip and re-run this script."
    fi

    # Create lib folders if necessary
    mkdir -p "$DIR_LIB_GEN" && mkdir -p "$DIR_LIB_RT" && mkdir -p "$DIR_LIB_GRADLE"

    ############################################################################
    #
    # Download project repositories if necessary
    #
    echo "Setting up project repositories ... "
    cd "$DIR_REPOS" && ./get_repos.sh

    ############################################################################
    #
    # Download Major
    #
    # Adapt Major's default wrapper scripts:
    # - set headless to true to support Chart on machines without X.
    # - do not mutate code unless an MML is specified (for historical reasons,
    #   major v1 was sometimes called without specifying an MML to simply act as
    #   javac; Major v2+'s default is to generate all mutants as opposed to none).
    #
    echo
    echo "Setting up Major ... "
    MAJOR_VERSION="3.0.1"
    MAJOR_URL="https://mutation-testing.org/downloads"
    MAJOR_ZIP="major-${MAJOR_VERSION}_jre11.zip"
    cd "$BASE" && rm -rf major \
               && download_url_and_unzip "$MAJOR_URL/$MAJOR_ZIP" \
               && rm "$MAJOR_ZIP" \
               && perl -pi -e '$_ .= qq(    -Djava.awt.headless=true \\\n) if /CodeCacheSize/' \
                    major/bin/ant \
               && perl -pi -e '$_ .= qq(\nif [ -z "\$MML" ]; then javac \$*; exit \$?; fi\n) if /^REFACTOR=/' \
                    major/bin/major \
               && perl -pi -e '$_ = qq(REFACTOR=\${REFACTOR:-"enable.decl.refactor enable.method.refactor"}\n) if /^REFACTOR=/' \
                    major/bin/major \


    ################################################################################
    #
    # Setup Mutation Tools folder
    #
    echo
    echo "Setting up Mutation Tools ... "
    MUTOOLS="$BASE/mutation_tools"
    mkdir -p $MUTOOLS


    ################################################################################
    #
    # Setup Junit libs
    #
    echo
    echo "Setting up Junit libs for Analyzer ... "

    JUNIT_VERSION="4.12"
    JUNIT_JAR="junit-$JUNIT_VERSION.jar"
    JUNIT_URL="https://repo1.maven.org/maven2/junit/junit/$JUNIT_VERSION/$JUNIT_JAR"

    JUNIT_JUPITER_VERSION="5.8.2"
    JUNIT_JUPITER_API_JAR="junit-jupiter-api-$JUNIT_JUPITER_VERSION.jar"
    JUNIT_JUPITER_ENGINE_JAR="junit-jupiter-engine-$JUNIT_JUPITER_VERSION.jar"
    JUNIT_VINTAGE_ENGINE_JAR="junit-vintage-engine-$JUNIT_JUPITER_VERSION.jar"
    JUNIT_JUPITER_API_URL="https://repo1.maven.org/maven2/org/junit/jupiter/junit-jupiter-api/$JUNIT_JUPITER_VERSION/$JUNIT_JUPITER_API_JAR"
    JUNIT_JUPITER_ENGINE_URL="https://repo1.maven.org/maven2/org/junit/jupiter/junit-jupiter-engine/$JUNIT_JUPITER_VERSION/$JUNIT_JUPITER_ENGINE_JAR"
    JUNIT_VINTAGE_ENGINE_URL="https://repo1.maven.org/maven2/org/junit/vintage/junit-vintage-engine/$JUNIT_JUPITER_VERSION/$JUNIT_VINTAGE_ENGINE_JAR"

    JUNIT_ADDONS_VERSION="1.4"
    JUNIT_ADDONS_JAR="junit-addons-$JUNIT_ADDONS_VERSION.jar"
    JUNIT_ADDONS_URL="https://repo1.maven.org/maven2/junit-addons/junit-addons/$JUNIT_ADDONS_VERSION/$JUNIT_ADDONS_JAR"

    cd "$MUTOOLS" && mkdir -p lib \
                && download_url $JUNIT_URL && mv $JUNIT_JAR lib/ \
                && download_url $JUNIT_ADDONS_URL && mv $JUNIT_ADDONS_JAR lib/ \
                && download_url $JUNIT_JUPITER_API_URL && mv $JUNIT_JUPITER_API_JAR lib/ \
                && download_url $JUNIT_JUPITER_ENGINE_URL && mv $JUNIT_JUPITER_ENGINE_JAR lib/ \
                && download_url $JUNIT_VINTAGE_ENGINE_URL && mv $JUNIT_VINTAGE_ENGINE_JAR lib/


    ################################################################################
    #
    # Setup PIT
    #
    echo
    echo "Setting up Pitest ... "

    PITEST_VERSION="1.9.0"
    PITEST_JUNIT_PLUGIN_VERSION="1.1.2"
    JUNIT_PLATFORM_VERSION="1.9.2"

    PITEST_JAR_DIR="$MUTOOLS/pitest-$PITEST_VERSION-jars"
    mkdir -p "$PITEST_JAR_DIR"

    JUNIT_PLATFORM="https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/$JUNIT_PLATFORM_VERSION/junit-platform-console-standalone-$JUNIT_PLATFORM_VERSION.jar"
    PITEST_JUNIT5="https://repo1.maven.org/maven2/org/pitest/pitest-junit5-plugin/$PITEST_JUNIT_PLUGIN_VERSION/pitest-junit5-plugin-$PITEST_JUNIT_PLUGIN_VERSION.jar"
    PITEST="https://repo1.maven.org/maven2/org/pitest/pitest/$PITEST_VERSION/pitest-$PITEST_VERSION.jar"
    PITEST_ENTRY="https://repo1.maven.org/maven2/org/pitest/pitest-entry/$PITEST_VERSION/pitest-entry-$PITEST_VERSION.jar"
    PITEST_CLI="https://repo1.maven.org/maven2/org/pitest/pitest-command-line/$PITEST_VERSION/pitest-command-line-$PITEST_VERSION.jar"

    cd "$PITEST_JAR_DIR" && download_url "$PITEST" \
                        && download_url "$PITEST_ENTRY" \
                        && download_url "$PITEST_CLI" \


    ############################################################################
    #
    # Download EvoSuite
    #
    echo
    echo "Setting up EvoSuite ... "
    EVOSUITE_VERSION="1.1.0"
    EVOSUITE_URL="https://github.com/EvoSuite/evosuite/releases/download/v${EVOSUITE_VERSION}"
    EVOSUITE_JAR="evosuite-${EVOSUITE_VERSION}.jar"
    EVOSUITE_RT_JAR="evosuite-standalone-runtime-${EVOSUITE_VERSION}.jar"
    cd "$DIR_LIB_GEN" && download_url "$EVOSUITE_URL/$EVOSUITE_JAR"
    cd "$DIR_LIB_RT"  && download_url "$EVOSUITE_URL/$EVOSUITE_RT_JAR"
    # Set symlinks for the supported version of EvoSuite
    (cd "$DIR_LIB_GEN" && ln -sf "$EVOSUITE_JAR" "evosuite-current.jar")
    (cd "$DIR_LIB_RT" && ln -sf "$EVOSUITE_RT_JAR" "evosuite-rt.jar")

    ############################################################################
    #
    # Download Randoop
    #
    echo
    echo "Setting up Randoop ... "
    RANDOOP_VERSION="4.3.3"
    RANDOOP_URL="https://github.com/randoop/randoop/releases/download/v${RANDOOP_VERSION}"
    RANDOOP_ZIP="randoop-${RANDOOP_VERSION}.zip"
    RANDOOP_JAR="randoop-all-${RANDOOP_VERSION}.jar"
    REPLACECALL_JAR="replacecall-${RANDOOP_VERSION}.jar"
    COVEREDCLASS_JAR="covered-class-${RANDOOP_VERSION}.jar"
    (cd "$DIR_LIB_GEN" && download_url_and_unzip "$RANDOOP_URL/$RANDOOP_ZIP")
    # Set symlink for the supported version of Randoop
    (cd "$DIR_LIB_GEN" && ln -sf "randoop-${RANDOOP_VERSION}/$RANDOOP_JAR" "randoop-current.jar")
    (cd "$DIR_LIB_GEN" && ln -sf "randoop-${RANDOOP_VERSION}/$REPLACECALL_JAR" "replacecall-current.jar")
    (cd "$DIR_LIB_GEN" && ln -sf "randoop-${RANDOOP_VERSION}/$COVEREDCLASS_JAR" "covered-class-current.jar")
    (cd "$DIR_LIB_GEN" && ln -sf "randoop-${RANDOOP_VERSION}/jacocoagent.jar" "jacocoagent.jar")

    ############################################################################
    #
    # Download build system dependencies
    #
    echo
    echo "Setting up Gradle dependencies ... "

    cd "$DIR_LIB_GRADLE"

    GRADLE_DISTS_ZIP=defects4j-gradle-dists-v3.zip
    GRADLE_DEPS_ZIP=defects4j-gradle-deps-v3.zip

    old_dists_ts=0
    old_deps_ts=0

    if [ -e $GRADLE_DISTS_ZIP ]; then
        old_dists_ts=$(get_modification_timestamp $GRADLE_DISTS_ZIP)
    fi
    if [ -e $GRADLE_DEPS_ZIP ]; then
        old_deps_ts=$(get_modification_timestamp $GRADLE_DEPS_ZIP)
    fi

    # Only download archive if the server has a newer file
    download_url $HOST_URL/$GRADLE_DISTS_ZIP
    download_url $HOST_URL/$GRADLE_DEPS_ZIP
    new_dists_ts=$(get_modification_timestamp $GRADLE_DISTS_ZIP)
    new_deps_ts=$(get_modification_timestamp $GRADLE_DEPS_ZIP)

    # Update gradle distributions/dependencies if a newer archive was available
    [ "$old_dists_ts" != "$new_dists_ts" ] && mkdir "dists" && unzip -q -u $GRADLE_DISTS_ZIP -d "dists"
    [ "$old_deps_ts" != "$new_deps_ts" ] && unzip -q -u $GRADLE_DEPS_ZIP

    cd "$BASE"

    ############################################################################
    #
    # Download utility programs
    #
    echo
    echo "Setting up utility programs ... "

    BUILD_ANALYZER_VERSION="0.0.1"
    BUILD_ANALYZER_JAR=build-analyzer-$BUILD_ANALYZER_VERSION.jar
    BUILD_ANALYZER_URL="https://github.com/jose/build-analyzer/releases/download/v$BUILD_ANALYZER_VERSION/$BUILD_ANALYZER_JAR"
    BUILD_ANALYZER_JAR_LOCAL="analyzer.jar"
    cd "$BASE/framework/lib" && download_url "$BUILD_ANALYZER_URL"
    rm -f "$BUILD_ANALYZER_JAR_LOCAL"
    ln -s "$BUILD_ANALYZER_JAR" "$BUILD_ANALYZER_JAR_LOCAL"

    echo
    echo "Defects4J successfully initialized."
    echo
    echo "|------------------------------------------------------------------------|"
    echo "|                           Defects4J version 3                          |"
    echo "|------------------------------------------------------------------------|"
    echo "| PLEASE READ:                                                           |"
    echo "| https://github.com/rjust/defects4j/?tab=readme-ov-file#reproducibility |"
    echo "|------------------------------------------------------------------------|"
    echo "| Important changes:                                                     |"
    echo "|   * Java 11 is required                                                |"
    echo "|   * Randoop v4.3.3                                                     |"
    echo "|   * Major v3.0.1                                                       |"
    echo "|------------------------------------------------------------------------|"
}

################################################################################
#
# Utility functions
#

# Print an error message and terminate the script.
# Takes one argument, a custom error message.
# Prints the supplied error message and a script termination notice to stderr.
# Terminates the script with exit code 1.
print_error_and_exit() {
  echo -e "${1} \nTerminating initialization... " >&2
  exit 1
}

# MacOS does not install the timeout command by default.
if [ "$(uname)" = "Darwin" ] ; then
  function timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fi

# Download the remote resource to a local file of the same name.
# Takes a single argument, a URL.
# Skips the download if the remote resource is newer.
# Works around connections that hang.
download_url() {
    if [ "$#" -ne 1 ]; then
        echo "Illegal number of arguments"
    fi
    URL=$1
    echo "Downloading ${URL}"
    if [ "$(uname)" = "Darwin" ] ; then
        wget -nv -N "$URL" || print_error_and_exit "Could not download $URL"
        echo "Downloaded $URL"
    else
        BASENAME="$(basename "$URL")"
        if [ -f "$BASENAME" ]; then
            ZBASENAME="-z $BASENAME"
        else
            ZBASENAME=""
        fi
        (timeout 300 curl -s -S -R -L -O "$ZBASENAME" "$URL" || (echo "retrying curl $URL" && rm -f "$BASENAME" && curl -R -L -O "$URL")) && echo "Downloaded $URL"
    fi
}

# Download the remote resource and unzip it.
# Takes a single argument, a URL.
# Skips the download if the local file of the same name is newer.
# Works around connections that hang and corrupted downloads.
download_url_and_unzip() {
    if [ "$#" -ne 1 ]; then
        echo "Illegal number of arguments"
    fi
    URL=$1
    BASENAME="$(basename "$URL")"
    download_url "$URL"
    if ! unzip -o "$BASENAME" > /dev/null ; then
        echo "retrying download and unzip"
        rm -rf "$BASENAME"
        download_url "$URL"
        unzip -o "$BASENAME"
    fi
}

# Get time of last data modification of a file
get_modification_timestamp() {
    local USAGE="Usage: get_modification_timestamp <file>"
    if [ "$#" != 1 ]; then
        print_error_and_exit "$USAGE"
    fi

    local f="$1"

    # The BSD version of stat does not support --version or -c
    if stat --version &> /dev/null; then
        # GNU version
        cmd="stat -c %Y $f"
    else
        # BSD version
        cmd="stat -f %m $f"
    fi

    local ts; ts=$($cmd)
    echo "$ts"
}

main
