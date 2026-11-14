.PHONY: format formatKotlin formatSwift formatDart checkFormatDart checkFormatKotlin checkFormatSwift checkApiDart updateApiDart analyzeDart installLinters test

format: formatSwift formatKotlin formatDart

installLinters:
	brew install ktlint
	brew install swiftformat

formatKotlin:
	ktlint --format --baseline=txlemetry_flutter/ktlint-baseline.xml txlemetry_flutter/android/**/*.kt

checkFormatKotlin:
	ktlint --baseline=txlemetry_flutter/ktlint-baseline.xml txlemetry_flutter/android/**/*.kt

# swiftlint darwin/txlemetry_flutter/Sources --fix conflicts with swiftformat
formatSwift:
	swiftformat txlemetry_flutter/darwin/txlemetry_flutter/Sources/txlemetry_flutter --swiftversion 5.3

checkFormatSwift:
	swiftformat txlemetry_flutter/darwin/txlemetry_flutter/Sources/txlemetry_flutter --swiftversion 5.3 --lint

formatDart:
	dart format .

checkFormatDart:
	dart format --set-exit-if-changed ./

analyzeDart:
	dart analyze .

checkApiDart:
	scripts/check-api-dart.sh

updateApiDart:
	scripts/check-api-dart.sh --update

test: 
	cd txlemetry_flutter && flutter test -r expanded
