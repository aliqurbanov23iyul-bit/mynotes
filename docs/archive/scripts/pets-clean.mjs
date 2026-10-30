import {readFileSync,writeFileSync} from 'node:fs';let s=readFileSync('assets/js/pets.js','utf8').replace('+PLACEHOLDER','');writeFileSync('assets/js/pets.js',s);
