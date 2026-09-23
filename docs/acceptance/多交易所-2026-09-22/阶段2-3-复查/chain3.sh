cd /Users/mdd/zhk/kanpan-wt-xchain-venue
export PATH=~/.rustup/toolchains/1.95.0-aarch64-apple-darwin/bin:$PATH
S=.vlogs/r3-summary.txt; rm -f $S
(cd Backend/kanpan-api && ../../scripts/machine-guard.sh run cargo test --lib) > .vlogs/r3-cargo.log 2>&1; echo "cargo EXIT=$?" >> $S
for t in core-test network-test data-test app-logic-test sync-contract account-test; do
  make $t > .vlogs/r3-$t.log 2>&1; echo "$t EXIT=$?" >> $S
done
echo "drift: $(git status --short -- ':!.vlogs' | tr '\n' ' ')" >> $S
make build DEVICE='iPhone 17 Pro Max' > .vlogs/r3-build.log 2>&1; echo "build EXIT=$?" >> $S
while pgrep -f "xcodebuild test.*D4A341CA" >/dev/null; do sleep 5; done
make chart-test DEVICE='iPhone 17 Pro Max' > .vlogs/r3-chart-test.log 2>&1; echo "chart-test EXIT=$?" >> $S
echo DONE >> $S
