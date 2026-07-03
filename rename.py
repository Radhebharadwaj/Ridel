import os
import glob

# Files to update
files = glob.glob('lib/**/*.dart', recursive=True)

for file in files:
    with open(file, 'r') as f:
        content = f.read()
    
    new_content = content.replace('tappedPlaceFromMap', 'activeDestination')
    new_content = new_content.replace('setTappedPlace', 'setActiveDestination')
    new_content = new_content.replace('clearTappedPlace', 'clearActiveDestination')
    
    if content != new_content:
        with open(file, 'w') as f:
            f.write(new_content)
        print(f"Updated {file}")
