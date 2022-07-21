#!/usr/bin/env bash
set -e 
set -o pipefail
# use TESTPATH given by environment, otherwise perform test in home directory
export TESTPATH="${TESTPATH:=/home/ubuntu}"
echo "**** PERFORMING UPDATE OF FLOX AGAINST LATEST RELEASE ****"
export TERM="xterm-256color"
#here we update the system installed version of flox to test against
sudo apt update
sudo apt --only-upgrade install flox
flox --version
echo "**** PERFORMING FLOX DEFAULT TEMPLATE INTEGRATION TEST ****"
#now we use the built version of capacitor from the PR or commit on gh to perform tests
rm -rf "$TESTPATH"/myproj
mkdir -p "$TESTPATH"/myproj && cd "$TESTPATH"/myproj
#Download latest version of tests to run
curl -O https://raw.githubusercontent.com/flox/floxpkgs/master/test/capacitor-flox-init-default.exp
curl -O https://raw.githubusercontent.com/flox/floxpkgs/master/test/capacitor-default.exp
curl -O https://raw.githubusercontent.com/flox/floxpkgs/master/test/default.bats 
#Run tests with expect
expect capacitor-flox-init-default.exp
expect capacitor-default.exp
