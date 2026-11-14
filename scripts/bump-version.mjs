import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const version = process.argv[2]
if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version ?? '')) {
    throw new Error('Usage: node scripts/bump-version.mjs <version>')
}
const replacements = [
    ['txlemetry_flutter/darwin/txlemetry_flutter/Sources/txlemetry_flutter/TxlemetryFlutterVersion.swift', /txlemetryFlutterVersion = "[^"]+"/g, `txlemetryFlutterVersion = "${version}"`],
    ['txlemetry_flutter/android/src/main/kotlin/com/txlemetry/flutter/TxlemetryVersion.kt', /txlemetryVersion = "[^"]+"/g, `txlemetryVersion = "${version}"`],
    ['txlemetry_flutter/lib/src/txlemetry_flutter_version.dart', /txlemetryFlutterVersion = '[^']+'/g, `txlemetryFlutterVersion = '${version}'`],
    ['txlemetry_flutter/pubspec.yaml', /^version: .+$/gm, `version: ${version}`],
    ['txlemetry_flutter/darwin/txlemetry_flutter.podspec', /s\.version\s*= '[^']+'/g, `s.version          = '${version}'`],
    ['txlemetry_flutter/android/build.gradle', /^version '[^']+'/gm, `version '${version}'`],
].map(([relative, pattern, replacement]) => {
    const filename = path.join(root, relative)
    const contents = fs.readFileSync(filename, 'utf8')
    if ([...contents.matchAll(pattern)].length !== 1) throw new Error(`Expected one version field: ${relative}`)
    return { filename, contents: contents.replace(pattern, replacement) }
})
const metadataPath = path.join(root, 'txlemetry_flutter/package.json')
const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'))
if (metadata.name !== 'txlemetry_flutter') throw new Error('Unexpected Flutter release metadata package name')
metadata.version = version
replacements.push({ filename: metadataPath, contents: JSON.stringify(metadata, null, 2) + '\n' })
for (const { filename, contents } of replacements) fs.writeFileSync(filename, contents)
console.log(`Aligned Flutter, Dart, Kotlin, Swift and release metadata to ${version}`)
