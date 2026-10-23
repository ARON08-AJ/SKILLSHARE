const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function renderUmlBox(box) {
  const { id, x, y, width, title, attributes, methods } = box;
  const headerHeight = 32;
  const linePadding = 5;
  const lineHeight = 18.5;
  
  const attrHeight = Math.max(attributes.length * lineHeight + linePadding * 2, 22);
  const methodHeight = Math.max(methods.length * lineHeight + linePadding * 2, 22);
  const totalHeight = headerHeight + attrHeight + methodHeight;
  
  box.height = totalHeight;
  box.headerHeight = headerHeight;
  box.attrHeight = attrHeight;
  box.methodHeight = methodHeight;
  
  let svg = `
  <!-- Box: ${title} -->
  <g id="box_${id}" transform="translate(${x}, ${y})">
    <rect x="0" y="0" width="${width}" height="${totalHeight}" fill="#ffffff" stroke="#666666" stroke-width="1.2" />
    
    <!-- Header Compartment -->
    <rect x="0" y="0" width="${width}" height="${headerHeight}" fill="#eeeeee" stroke="#666666" stroke-width="1.2" />
    <text x="${width / 2}" y="${headerHeight / 2 + 5}" font-family="'Segoe UI', Helvetica, Arial, sans-serif" font-size="14" font-weight="bold" fill="#000000" text-anchor="middle">${title}</text>
    
    <!-- Attributes Compartment -->
    <g transform="translate(10, ${headerHeight + linePadding})">
`;

  attributes.forEach((attr, idx) => {
    svg += `      <text x="0" y="${idx * lineHeight + 13}" font-family="'Segoe UI', Helvetica, Arial, sans-serif" font-size="12.5" fill="#000000">${attr}</text>\n`;
  });

  svg += `    </g>
    
    <!-- Methods Divider -->
    <line x1="0" y1="${headerHeight + attrHeight}" x2="${width}" y2="${headerHeight + attrHeight}" stroke="#666666" stroke-width="1.2" />
    
    <!-- Methods Compartment -->
    <g transform="translate(10, ${headerHeight + attrHeight + linePadding})">
`;

  methods.forEach((m, idx) => {
    svg += `      <text x="0" y="${idx * lineHeight + 13}" font-family="'Segoe UI', Helvetica, Arial, sans-serif" font-size="12.5" fill="#000000">${m}</text>\n`;
  });

  svg += `    </g>
  </g>
`;
  return svg;
}

// Boxes definition
const boxes = [
  {
    id: 'user',
    title: 'User',
    x: 470,
    y: 20,
    width: 210,
    attributes: [
      '+String userId',
      '+String name',
      '+String email',
      '+String role'
    ],
    methods: [
      '+signUpWithEmail()',
      '+signInWithEmail()',
      '+updateUserProfile()'
    ]
  },
  {
    id: 'skilledProfile',
    title: 'SkilledProfile',
    x: 25,
    y: 335,
    width: 235,
    attributes: [
      '+String skilledProfileId',
      '+String professionTitle',
      '+String verificationStatus'
    ],
    methods: [
      '+getSkilledUserProfile()',
      '+updateSkilledUserProfile()',
      '+getUserPortfolio()'
    ]
  },
  {
    id: 'companyProfile',
    title: 'CompanyProfile',
    x: 300,
    y: 335,
    width: 235,
    attributes: [
      '+String companyProfileId',
      '+String companyName',
      '+String industry'
    ],
    methods: [
      '+getCompanyProfile()',
      '+updateCompanyProfile()',
      '+streamCompanyJobs()'
    ]
  },
  {
    id: 'customerProfile',
    title: 'CustomerProfile',
    x: 575,
    y: 335,
    width: 245,
    attributes: [
      '+String customerProfileId',
      '+String address',
      '+String gpsLocation'
    ],
    methods: [
      '+getCustomerProfile()',
      '+updateCustomerProfile()',
      '+customerProfileStream()'
    ]
  },
  {
    id: 'chat',
    title: 'Chat',
    x: 865,
    y: 335,
    width: 215,
    attributes: [
      '+String chatId',
      '+String chatType'
    ],
    methods: [
      '+getMessages()',
      '+sendMessage()',
      '+deleteChat()'
    ]
  },
  {
    id: 'product',
    title: 'Product',
    x: 35,
    y: 655,
    width: 215,
    attributes: [
      '+String productId',
      '+String title',
      '+double price'
    ],
    methods: [
      '+createProduct()',
      '+updateProduct()',
      '+deleteProduct()'
    ]
  },
  {
    id: 'job',
    title: 'Job',
    x: 310,
    y: 655,
    width: 215,
    attributes: [
      '+String jobId',
      '+String title',
      '+String status'
    ],
    methods: [
      '+createJob()',
      '+applyForJob()',
      '+updateJob()'
    ]
  },
  {
    id: 'order',
    title: 'Order',
    x: 540,
    y: 645,
    width: 250,
    attributes: [
      '+String orderId',
      '+double totalAmount',
      '+String status',
      '+String deliveryPartnerId',
      '+String deliveryStatus',
      '+String deliveryOtp',
      '+String pickupAddress',
      '+String shippingAddress'
    ],
    methods: [
      '+addToCart()',
      '+checkoutCart()',
      '+updateOrderStatus()'
    ]
  },
  {
    id: 'review',
    title: 'Review',
    x: 825,
    y: 645,
    width: 255,
    attributes: [
      '+String reviewId',
      '+int rating',
      '+String comment'
    ],
    methods: [
      '+createReview()',
      '+getUserReviews()',
      '+toggleCompanyEndorsement()'
    ]
  }
];

let boxesSvg = '';
boxes.forEach(b => {
  boxesSvg += renderUmlBox(b);
});

// Arrow connections definition
const linesSvg = `
  <!-- Association Lines with Navigation Arrows & Multiplicities -->
  
  <!-- 1. User -> SkilledProfile -->
  <path d="M 470 175 C 320 200, 160 235, 142 332" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="450" y="178" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="148" y="322" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  
  <!-- 2. User -> CompanyProfile -->
  <path d="M 505 198 C 465 240, 425 280, 417 332" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="480" y="222" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="424" y="322" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  
  <!-- 3. User -> CustomerProfile -->
  <path d="M 645 198 C 675 240, 692 280, 697 332" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="655" y="222" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="704" y="322" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  
  <!-- 4. User -> Chat -->
  <path d="M 680 175 C 810 200, 940 235, 972 332" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="695" y="178" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
  <text x="980" y="322" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
  
  <!-- 5. SkilledProfile -> Product -->
  <path d="M 142 501 L 142 652" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="130" y="525" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="150" y="642" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
  
  <!-- 6. CompanyProfile -> Job -->
  <path d="M 417 501 L 417 652" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="405" y="525" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="425" y="642" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
  
  <!-- 7. CustomerProfile -> Order -->
  <path d="M 665 501 C 658 545, 660 590, 665 642" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="648" y="525" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="674" y="635" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
  
  <!-- 8. CustomerProfile -> Review -->
  <path d="M 760 501 C 815 545, 910 590, 952 642" fill="none" stroke="#555555" stroke-width="1.3" marker-end="url(#umlArrow)" />
  <text x="748" y="525" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">1</text>
  <text x="960" y="635" font-family="'Segoe UI', Arial, sans-serif" font-size="12" font-weight="bold" fill="#333333">*</text>
`;

const fullHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Entity-Relationship Diagram</title>
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background-color: #ffffff;
      width: 1110px;
      height: 940px;
      overflow: hidden;
    }
  </style>
</head>
<body>
  <svg xmlns="http://www.w3.org/2000/svg" width="1110" height="940" viewBox="0 0 1110 940">
    <defs>
      <!-- UML Open Navigation Arrow Marker -->
      <marker id="umlArrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse">
        <polyline points="1,1.5 7,5 1,8.5" fill="none" stroke="#555555" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
      </marker>
    </defs>
    
    <!-- Background -->
    <rect width="100%" height="100%" fill="#ffffff" />
    
    <!-- Connecting Lines -->
    ${linesSvg}
    
    <!-- UML Classes -->
    ${boxesSvg}
  </svg>
</body>
</html>`;

const tempDir = path.join(__dirname, '.temp_diagram');
if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

const htmlFilePath = path.join(tempDir, 'er_diagram.html');
fs.writeFileSync(htmlFilePath, fullHtml, 'utf-8');

const workspaceDir = path.resolve(__dirname, '..');
const outputImagePathInWorkspace = path.join(workspaceDir, 'assets', 'images', 'er_diagram_updated.png');
const outputImagePathRoot = path.join(workspaceDir, 'er_diagram_updated.png');
const artifactsDir = 'C:\\\\Users\\\\aronj\\\\.gemini\\\\antigravity-ide\\\\brain\\\\6424163c-96eb-4838-9c8b-bf2c61851d53';
const outputImagePathArtifact = path.join(artifactsDir, 'er_diagram_updated.png');

fs.mkdirSync(path.dirname(outputImagePathInWorkspace), { recursive: true });
fs.mkdirSync(artifactsDir, { recursive: true });

const chromePath = 'C:\\\\Program Files\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe';
const cmd = `"${chromePath}" --headless --disable-gpu --screenshot="${outputImagePathInWorkspace}" --window-size=1110,940 --default-background-color=00000000 "${htmlFilePath}"`;

console.log('Rendering high resolution ER diagram screenshot...');
execSync(cmd, { stdio: 'inherit' });

fs.copyFileSync(outputImagePathInWorkspace, outputImagePathRoot);
if (fs.existsSync(artifactsDir)) {
  fs.copyFileSync(outputImagePathInWorkspace, outputImagePathArtifact);
}

console.log('Done! Successfully generated and saved to all locations.');
