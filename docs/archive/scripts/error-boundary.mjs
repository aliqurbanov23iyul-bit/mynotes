import {readFileSync,writeFileSync} from 'node:fs';let s=readFileSync('assets/js/theme.js','utf8');s="import './errors.js';\n"+s;writeFileSync('assets/js/theme.js',s);
