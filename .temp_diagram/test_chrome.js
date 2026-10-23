const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const htmlContent = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Test</title>
</head>
<body style="background: white; margin: 0; padding: 20px;">
  <h1 style="color: blue;">Test Title</h1>
</body>
</html>`;

const tempDir = path.join(__dirname, '.temp_diagram');
if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

const htmlPath = path.join(tempDir, 'test.html');
const imgPath = path.join(tempDir, 'test.png');

fs.writeFileSync(htmlPath, htmlContent);

const chromePath = 'C:\\\\Program Files\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe';
const cmd = `"${chromePath}" --headless --disable-gpu --screenshot="${imgPath}" --window-size=800,600 "${htmlPath}"`;

try {
  execSync(cmd, { stdio: 'inherit' });
  console.log('Success! Image created:', fs.existsSync(imgPath), imgPath);
} catch (e) {
  console.error('Error:', e);
}
