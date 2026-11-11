"""Generate a dependency-free Xcode project and sync the Android game-entry template.

Run from any OS: python iOSClient/tools/generate_project.py
No developer credentials, CDKs, game tokens, or server keys belong in this project.
"""
from pathlib import Path
import hashlib
import re
import json

ROOT = Path(__file__).resolve().parents[1]


def uid(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def generate():
    android = ROOT.parent / 'H5Duokai/app/src/main/java/cn/duokai/workspace/GameStartScript.java'
    text = android.read_text(encoding='utf-8')
    code = re.search(r'return """\n(.*?)\n\s*"""\.replace', text, re.S).group(1)
    lines = code.splitlines()
    indent = min(len(line) - len(line.lstrip()) for line in lines if line.strip())
    (ROOT / 'Resources/game-start.js').write_text('\n'.join(line[indent:] for line in lines) + '\n', encoding='utf-8')

    objects = []

    def add(key, body):
        objects.append(f'\t\t{uid(key)} = {{ {body} }};')
        return uid(key)

    def refs(items):
        return '(' + ', '.join(items) + ',)'

    source_builds, resources, test_builds, files = [], [], [], []
    for pattern, kind in [('Sources/*.swift', 'source'), ('Resources/*', 'resource'), ('Tests/*.swift', 'test')]:
        for file in sorted(ROOT.glob(pattern)):
            relative = file.relative_to(ROOT).as_posix()
            typ = 'sourcecode.swift' if file.suffix == '.swift' else 'text'
            file_id = add('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {quote(relative)}; sourceTree = "<group>";')
            files.append(file_id)
            build_id = add('build:' + relative, f'isa = PBXBuildFile; fileRef = {file_id};')
            {'source': source_builds, 'resource': resources, 'test': test_builds}[kind].append(build_id)

    app_product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Lanpangzi.app; sourceTree = BUILT_PRODUCTS_DIR;')
    test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = LanpangziTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    plist = add('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
    products = add('products', f'isa = PBXGroup; children = {refs([app_product, test_product])}; name = Products; sourceTree = "<group>";')
    group = add('group', f'isa = PBXGroup; children = {refs(files + [plist, products])}; sourceTree = "<group>";')
    phases = []
    for name, typ, entries in [('sources', 'Sources', source_builds), ('resources', 'Resources', resources), ('frameworks', 'Frameworks', [])]:
        phases.append(add(name, f'isa = PBX{typ}BuildPhase; buildActionMask = 2147483647; files = {refs(entries) if entries else "()"}; runOnlyForDeploymentPostprocessing = 0;'))
    tests_phase = add('test-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(test_builds)}; runOnlyForDeploymentPostprocessing = 0;')

    for scope in ['project', 'app', 'tests']:
        configs = []
        for mode in ['Debug', 'Release']:
            settings = {
                'project': 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = targeted;',
                'app': 'PRODUCT_NAME = Lanpangzi; PRODUCT_BUNDLE_IDENTIFIER = cn.duokai.ios; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;',
                'tests': 'PRODUCT_NAME = LanpangziTests; PRODUCT_BUNDLE_IDENTIFIER = cn.duokai.ios.tests; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Lanpangzi.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Lanpangzi"; BUNDLE_LOADER = "$(TEST_HOST)";'
            }[scope]
            if scope == 'project':
                settings += (' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode == 'Debug'
                             else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
            configs.append(add(scope + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};'))
        add(scope + '-configs', f'isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

    add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("app-configs")}; buildPhases = {refs(phases)}; buildRules = (); dependencies = (); name = Lanpangzi; productName = Lanpangzi; productReference = {app_product}; productType = "com.apple.product-type.application";')
    proxy = add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("app-target")}; remoteInfo = Lanpangzi;')
    dependency = add('dependency', f'isa = PBXTargetDependency; target = {uid("app-target")}; targetProxy = {proxy};')
    add('test-target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("tests-configs")}; buildPhases = {refs([tests_phase])}; buildRules = (); dependencies = {refs([dependency])}; name = LanpangziTests; productName = LanpangziTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
    add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; knownRegions = (en, "zh-Hans", Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([uid("app-target"), uid("test-target")])};')
    project = ROOT / 'Lanpangzi.xcodeproj'
    project.mkdir(exist_ok=True)
    (project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n', encoding='utf-8')
    scheme = project / 'xcshareddata/xcschemes'
    scheme.mkdir(parents=True, exist_ok=True)

    def build_ref(target, name):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Lanpangzi.xcodeproj"/>'

    app = build_ref('app-target', 'Lanpangzi.app')
    tests = build_ref('test-target', 'LanpangziTests.xctest')
    (scheme / 'Lanpangzi.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{tests}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
    print('Generated Lanpangzi.xcodeproj and synced Android game-start.js')


if __name__ == '__main__':
    generate()
