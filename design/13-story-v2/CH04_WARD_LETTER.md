# 第四章病房回訪：她留下的信

床頭櫃解開後，直接互動仍先顯示公用取件聯的摘要。凜可以問棠能不能讀上層的信，或關上櫃門。棠只同意聽四名聯絡人的名字。聽完的玩家可以抄下四處地點，或把原信放回她伸手可及的位置。

- 入口沿用真實病房、訪客動線與床頭櫃。已有探訪同意與公用取件聯才提供詢問選項，辦公室的歷史回放無法代替。
- 只有完成自己抄寫名單的對話才將筆記與完成旗標一起存入目前存檔。中途取消或選擇離開時可以重新詢問。已抄寫仍可回來讀信，筆記不用重複抄寫。
- 保留原信與既有公用取件聯。這段回訪沒有報酬、任務地圖標記或章節推進。
- 上層低走道的舊圍巾可另外調查。標籤只顯示床位，圍巾歸屬留待故事交代。視覺沿用場景道具圖層與病房光照。

## 圍巾來源

以病房床頭櫃素材當成造型、透視及線條參考。原件保留於生成工作區，遊戲圖裁成 74 × 200 的透明 PNG，另以專案的 NormalMapMaker 產生配套法線。遊戲中的尺寸是 13 × 36。

### 生成描述

> Use case: illustration-story. Asset type: one small transparent environmental sprite for Nest Egg, a hand-drawn 2D side-view cyberpunk adventure. Input image 1 is a style and viewing-angle reference only. Create one old scarf draped over a single wall hook in a quiet nursing ward. The hook is a tiny flat brushed-metal wall plate with two visible screw dots and a short hook. The scarf bends densely around the hook and falls in two asymmetric lengths, muted plum and steel blue woven fabric, two broad folds, minimal fringe, a tiny plain cream bed tag sewn to an end with no legible text. Use the reference's precise clean blue-gray ink outlines, crisp flat color areas and warm left light, grounded handcrafted illustration with a few high-value edge accents. Side-on game camera with a slight top/side perspective matching the reference. Small memorable silhouette readable when cropped to 40 screen pixels high. Full single object centered with margin and sharp alpha. Transparent background. No furniture, walls, signage, labels with text, extra hooks, characters, fake checkerboard, floating shadows, lighting effects or vignette.

### 修整描述

> Edit the supplied transparent Nest Egg sprite for production. Preserve the same single hook, scarf silhouette, angular flat folds, plum and blue bands, small cream bed tag and side-view proportions. Make this an exact crisp cutout with genuinely transparent alpha directly outside the dark ink border: completely remove the entire soft orange, purple and blue halo, ambient glows or shadow outside the hook and fabric. The open gap between scarf tails must be completely transparent as well. Reduce overall visible stitch and weave noise to a handful of accents for a 2D 40 pixel house-scale prop. Do not add a wall, palette change, text, compositing background or any new elements. Keep clean sharp lines and solid flat color only on the object. Full asset in frame.
