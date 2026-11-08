#!/usr/bin/env python3
"""Generate the dependency-free Xcode app project; core remains a local SPM library."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def q(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
objects = []
def obj(name, value):
    key = ident(name)
    objects.append(f'{key} = {{ {value} }};')
    return key
sources = sorted((root / 'Sources/BetterApple').rglob('*.swift'))
refs, builds = [], []
for source in sources:
    path = source.relative_to(root)
    ref = obj(str(path), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(obj('build:' + str(path), f'isa = PBXBuildFile; fileRef = {ref};'))
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = BetterApple.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = obj('main-group', f'isa = PBXGroup; children = ({",".join(refs)},{products},); sourceTree = "<group>";')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core = obj('core-product', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = BetterAppleCore;')
core_build = obj('core-build', f'isa = PBXBuildFile; productRef = {core};')
phase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build},); runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ['Debug', 'Release']:
    release = config == 'Release'
    settings = f'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_OPTIMIZATION_LEVEL = {q("-O" if release else "-Onone")}; DEBUG_INFORMATION_FORMAT = {q("dwarf-with-dsym" if release else "dwarf")};'
    if not release:
        settings += ' SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ENABLE_TESTABILITY = YES; ONLY_ACTIVE_ARCH = YES;'
    project_configs.append(obj('project-' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};'))
    settings = 'PRODUCT_NAME = BetterApple; PRODUCT_BUNDLE_IDENTIFIER = app.betterapple.desktop; INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_ENTITLEMENTS = Resources/BetterApple.entitlements; ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";'
    target_configs.append(obj('target-' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};'))
project_list = obj('project-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = obj('target-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({phase},{frameworks},{resources},); buildRules = (); dependencies = (); name = BetterApple; packageProductDependencies = ({core},); productName = BetterApple; productReference = {product}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
folder = root / 'BetterApple.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
scheme_dir = folder / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="BetterApple.app" BlueprintName="BetterApple" ReferencedContainer="container:BetterApple.xcodeproj"/>'
(scheme_dir / 'BetterApple.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated app project with {len(sources)} source files.')
