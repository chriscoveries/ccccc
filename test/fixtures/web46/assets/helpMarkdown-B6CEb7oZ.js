var e=/^##(?!#)\s+.*$/,t=/^##\s*@role:\s*(\w+)\s*$/i,n=/^##\s*@actor:\s*(\S+)(?:\s+(.*\S))?\s*$/i,r=/^##\s*@pet\s*:?\s*$/i,i=/^##\s*@voice_secretary\s*:?\s*$/i;function a(t){let n=String(t||``).replace(/\r\n?/g,`
`);if(!n)return[``];let r=n.split(`
`),i=[],a=[];for(let t of r){if(e.test(t)&&a.length>0){i.push(a.join(`
`)),a=[t];continue}a.push(t)}return i.push(a.join(`
`)),i}function o(e){return String(e||``).trim()}function s(e){let a=String(e||``).replace(/\r\n?/g,`
`),s=a.split(`
`),c=String(s[0]||``),l=c.match(t);if(l){let e=String(l[1]||``).trim().toLowerCase(),t=o(s.slice(1).join(`
`));return e===`foreman`||e===`peer`?{kind:`role`,key:`role:${e}`,raw:o(a),body:t}:{kind:`extra`,key:`role:${e}`,raw:o(a),body:t}}let u=c.match(n);if(u){let e=String(u[1]||``).trim(),t=o([String(u[2]||``).trim(),...s.slice(1)].filter(Boolean).join(`
`));return{kind:e?`actor`:`extra`,key:e?`actor:${e}`:`actor:`,raw:o(a),body:t}}return r.test(c)?{kind:`extra`,key:`legacy:pet`,raw:o(a),body:o(s.slice(1).join(`
`))}:i.test(c)?{kind:`voice_secretary`,key:`voice_secretary`,raw:o(a),body:o(s.slice(1).join(`
`))}:null}function c(e){let t=a(e),n=[],r={},i=[],c=``,l=``,u=``;for(let e of t){let t=o(e);if(!t)continue;let a=s(t);if(!a){n.push(t);continue}if(a.kind===`role`){a.key===`role:foreman`?c=a.body:a.key===`role:peer`?l=a.body:i.push(a.raw);continue}if(a.kind===`actor`){let e=a.key.slice(6);e?r[e]=a.body:i.push(a.raw);continue}if(a.kind===`voice_secretary`){u=a.body;continue}i.push(a.raw)}return{common:n.join(`

`).trim(),foreman:c,peer:l,voiceSecretary:u,actorNotes:r,extraTaggedBlocks:i}}function l(e){let t=[],n=o(e.common),r=o(e.foreman),i=o(e.peer),a=o(e.voiceSecretary||``),s=e.actorNotes||{},c=Array.isArray(e.extraTaggedBlocks)?e.extraTaggedBlocks.map(o).filter(Boolean):[];n&&t.push(n),r&&t.push(`## @role: foreman\n\n${r}`),i&&t.push(`## @role: peer\n\n${i}`),a&&t.push(`## @voice_secretary\n\n${a}`);let l=new Set,u=[];for(let t of Array.isArray(e.actorOrder)?e.actorOrder:[]){let e=String(t||``).trim();!e||l.has(e)||(l.add(e),u.push(e))}for(let e of Object.keys(s).sort())l.has(e)||(l.add(e),u.push(e));for(let e of u){let n=o(s[e]);n&&t.push(`## @actor: ${e}\n\n${n}`)}t.push(...c);let d=t.filter(Boolean).join(`

`).trim();return d?`${d}\n`:``}function u(e,t,n,r){let i=c(e),a={...i.actorNotes},s=String(t||``).trim();return s&&(a[s]=o(n)),s&&!a[s]&&delete a[s],l({common:i.common,foreman:i.foreman,peer:i.peer,voiceSecretary:i.voiceSecretary,actorNotes:a,actorOrder:r,extraTaggedBlocks:i.extraTaggedBlocks})}export{c as n,u as r,l as t};