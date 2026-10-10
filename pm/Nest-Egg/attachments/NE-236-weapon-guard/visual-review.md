# 原生圖驗收界線

本階段驗近戰轉盾／真彈體／連段中斷。Godot4.7.2 Forward+、llvmpipe LLVM19.1.7、1280×720、camera zoom3.4、低粒子0.25、零震動、減閃；事件及輪詢均合成输入，Dummy音訊不證明人工音效試聽。圖片是各彈體完整接觸及反彈飛行後的實際狀態，並非有效命中瞬間或全動作逐格美術驗收。

- 第一次低品質試拍30張：功能320項通過，但固定4.2實際秒仍可能早於章節卡tween結束，鏡頭平滑未重設令人物腳部裁切。原始PNG及raw保留，圖片標rejected。
- 重拍：等待該Level內真正ChapterCard.finished；只重設驗證鏡頭的Camera2D smoothing，不修改Main/Level/ChapterCard/PlayerVisual或畫面內容。
- 原生檢視代表圖：首次低品質匕首右格擋（拒絕）、高品質匕首右格擋／右反彈、重錘左反彈、低品質長柄右反彈、熱刃左背面受傷。章節卡已退場，人物腳部可見；格擋首次提示仍可能遮頭，此圖不驗頭部接縫。
- 新觀察：低品質長柄右反彈圖中，50px長柄垂直向下穿過地面，末端在原生畫面底部裁出。共享持物／舉盾姿態不算通過；不縮短武器或遮擋地面換取美術通過。
- 武器掛點與角色接縫仍由原owner處理；敵人腰／胯缺口與近戰握持變體問題保留。沒有硬體GPU/HDR顯示器/VRAM、真人手把、人工手感、完整章節或全武器完成宣稱。

## 長柄持盾／待機接口需求（未實作）

來源game/player/player_visual.gd::_draw_melee_weapon：沿(hand_front.global_position-arm_front_lower.global_position).normalized()繪製，每種近戰visual_id空字串；長柄資料melee_length=50。收招轉盾後仍沿垂下的前臂畫長柄，未有武器專用持物／盾狀態掛點。

請角色owner沿既有近戰持物狀態及palm grip_offset接口，驗左右兩向的idle/block carry pose與長武器端點對真地面的關係；起手／ACTIVE時仍沿真正動作且不改hit窗口／碰撞距離，電話／死亡／受擊／載具優先序保持。近戰狀態不得冒稱持槍id；不得縮武器或硬改共享骨長遮掩。B可提供武器專用資料，但不修改CharacterRig/HumanoidAnimator/RigInput/PlayerVisual。此為觀察與要求，不代稱接口已存在或美術已完成。
