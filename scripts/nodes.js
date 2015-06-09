#!/usr/bin/env node

var data = '';

function withPipe(data) {
  var j = JSON.parse(data);

  for(k in j) {
    if (j[k].name.indexOf('node') !== -1) {
      console.log(j[k].name);
    }
  }
}

var self = process.stdin;
self.on('readable', function() {
  var chunk = this.read();
  if (chunk !== null) {
    data += chunk;
  }
});

self.on('end', function() {
  withPipe(data);
});
