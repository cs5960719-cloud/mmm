"""Check project wiring/resources on Windows; this is not a Swift compiler."""
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
plist = plistlib.loads((root / 'Info.plist').read_bytes())
assert plist['NSAppTransportSecurity'] == {'NSAllowsArbitraryLoadsInWebContent': True}
project = (root / 'Lanpangzi.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
definitions = re.findall(r'^\s*([A-F0-9]{24}) = \{', project, re.M)
assert len(definitions) == len(set(definitions)), 'duplicate project object identifiers'
references = set(re.findall(r'\b[A-F0-9]{24}\b', project))
assert references == set(definitions), 'unresolved project object identifiers'
for group in ['Sources', 'Resources', 'Tests']:
    for file in (root / group).iterdir():
        if file.suffix == '.cjs':
            continue
        assert file.relative_to(root).as_posix() in project, f'unregistered file: {file}'
scheme = ET.parse(root / 'Lanpangzi.xcodeproj/xcshareddata/xcschemes/Lanpangzi.xcscheme')
for reference in scheme.iter('BuildableReference'):
    assert reference.attrib['BlueprintIdentifier'] in references
entry = (root / 'Resources/game-start.js').read_text(encoding='utf-8')
assert entry.count('__CDK_SERVER__') == entry.count('__CDK_ROLE__') == 1
bridge = (root / 'Resources/bridge.js').read_text(encoding='utf-8')
assert bridge.count('__IOS_SESSION_TOKEN__') == 1
assert 'IPHONEOS_DEPLOYMENT_TARGET = 17.0' in project
print('PASS: project references, source/resource registration, scheme, plist, script templates (Swift compilation pending on Mac)')
