shader_type canvas_item;
// 搖動：植物被風吹（頂端擺動最大、根部不動），或懸掛物（衣繩、燈籠、纜線）頂端固定、底部擺動。
// 每個道具以所在位置錯開相位，不需要每影格腳本也不需要每個實體一份材質。
uniform float amplitude = 1.5;  // 擺動端的位移（邏輯像素；頂點座標是貼圖像素，所以除以節點的縮放換算）
uniform float speed = 1.1;
uniform bool hang = false;      // true：固定頂端、底部擺動

void vertex() {
	float height = clamp(hang ? UV.y : 1.0 - UV.y, 0.0, 1.0);
	float phase = MODEL_MATRIX[3].x * 0.07;
	float pixels_per_unit = max(length(MODEL_MATRIX[0].xy), 0.0001);
	VERTEX.x += amplitude / pixels_per_unit * height * height * sin(TIME * speed + phase);
}
