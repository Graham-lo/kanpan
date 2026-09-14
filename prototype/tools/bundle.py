import io, re, os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src'))
rd = lambda p: io.open(p, encoding='utf-8').read()
html = rd('index.html')
html = html.replace('<meta charset="utf-8">\n', '')
html = html.replace('<title>看盘</title>\n', '')
html = html.replace('<link rel="stylesheet" href="style.css">\n', '')
for f in ('data.js', 'styles.js', 'chart.js', 'app.js'):
    html = html.replace('<script src="%s"></script>\n' % f, '')
    html = html.replace('<script src="%s"></script>' % f, '')
parts = ['''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="format-detection" content="telephone=no">
<title>看盘</title>
<style>
''', rd('style.css'), '''
</style>
</head>
<body>
''', html.strip(), '''
<script>
''', rd('data.js'), '''
</script>
<script>
''', rd('styles.js'), '''
</script>
<script>
''', rd('chart.js'), '''
</script>
<script>
''', rd('app.js'), '''
</script>
</body>
</html>
''']
out = ''.join(parts)
io.open(os.path.join('..', '看盘原型.html'), 'w', encoding='utf-8').write(out)   # 输出到 prototype/ 根
print(len(out), 'script src left:', out.count('<script src='))
