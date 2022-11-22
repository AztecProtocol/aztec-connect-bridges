import re
from pathlib import Path

for path in Path('../typechain-types/').rglob('**/*'):
    
    if Path.is_file(path):
        with open(path, 'r') as file:
            data = file.read()
                                                
            # Fix the ones where we need index.js
            outer_pattern = '\* as \w* from \".*\";'
            to_fix = re.findall(outer_pattern, data)
            y = re.split(outer_pattern, data)
            
            replacements = []
            for x in to_fix:
                inner_pattern = "\* as \w* from \"(.*)\";"
                _x = re.search(inner_pattern, x)
                cleaned = "{0}/index.js".format(_x[1])
                rep = _x[0].replace(_x[1], cleaned)
                replacements.append(rep)
                    
            full = []
            for i in range(len(y)):
                full.append(y[i])
                if i < len(replacements):
                    full.append(replacements[i])
                    
            data = "".join(full)
            
            # The more direct .js ones
            outer_pattern = '\} from \"[.]{1,2}.*\";'
            to_fix = re.findall(outer_pattern, data)
            y = re.split(outer_pattern, data)
            
            replacements = []
            for x in to_fix:
                inner_pattern = "\} from \"[.]{1,2}(.*)\";"
                _x = re.search(inner_pattern, x)
                cleaned = "{0}.js".format(_x[1])
                rep = _x[0].replace(_x[1], cleaned)
                replacements.append(rep)
                    
            full = []
            for i in range(len(y)):
                full.append(y[i])
                if i < len(replacements):
                    full.append(replacements[i])
                    
            data = "".join(full)
      
        with open(path, 'w+') as f:
            f.write(data)