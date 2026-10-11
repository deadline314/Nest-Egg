shader_type canvas_item;
render_mode blend_mul, unshaded;
// 牆上的影子（BG-34）：畫在背牆的範圍上，把牆乘暗。
// silhouette 是只畫了會投影的東西（主角、敵人、人物）的低解析度畫面，和主畫面同一個鏡頭；
// 對牆上的每一點、每一盞燈，往燈的方向退回去取樣：那裡有東西擋著，這一點就在影子裡。
// 影子等於把輪廓以燈為中心放大，所以會偏向遠離燈的那一側；離燈越近放大得越多（影子越大），燈在正上方時影子落在腳邊。
// 垂直方向放大得比較少：頭頂的燈照理會把影子整個推到地板上，那一部分已經有腳下的接觸陰影，牆上留的是往旁邊偏的部分。

const int MAX_LIGHTS = 4;

uniform sampler2D silhouette : filter_linear, repeat_disable;
// 每盞燈兩組數字（分開的參數，不用陣列：每影格更新時不必配置新的陣列）。
// light：xy＝燈在畫面上的位置（0～1）、z＝光池半徑（以畫面高度為 1）、w＝這盞燈的亮度比例（0～1；熄滅、閃爍時跟著變）。
// cone：xy＝朝某個方向照的燈（槍燈）的方向、z＝張角的一半（弧度）；往四周照的燈 z 填 -2。
uniform vec4 light_0 = vec4(0.0);
uniform vec4 light_1 = vec4(0.0);
uniform vec4 light_2 = vec4(0.0);
uniform vec4 light_3 = vec4(0.0);
uniform vec4 cone_0 = vec4(0.0, 0.0, -2.0, 0.0);
uniform vec4 cone_1 = vec4(0.0, 0.0, -2.0, 0.0);
uniform vec4 cone_2 = vec4(0.0, 0.0, -2.0, 0.0);
uniform vec4 cone_3 = vec4(0.0, 0.0, -2.0, 0.0);
uniform int light_count = 0;
// 畫面的寬 ÷ 高。
uniform float aspect = 1.7778;
// 角色離牆多遠，相對於燈離角色多遠（x 橫向、y 垂直）：越大影子越大、偏得越多。
uniform vec2 depth = vec2(0.6, 0.16);
// 貼近燈的地方再多放大多少倍（0＝不管遠近都一樣大）。
uniform float near_boost = 0.7;
// 環境光的亮度（0～1）：環境越亮，擋住一盞燈的影響越小，影子越淡。
uniform float ambient = 0.25;
// 一盞正常亮度的燈在暗處的影子有多深；所有影子疊起來最多把牆壓暗多少（留一點底，暗處的牆才不會整片死黑）。
uniform float light_dark = 0.85;
uniform float max_dark = 0.82;
// 光源周圍多大的範圍內的東西不投影（以畫面高度為 1）：那是拿著或裝著這盞燈的東西自己。
uniform float own_radius = 0.05;
// 輪廓圖一個像素的大小（柔邊取樣用）。
uniform vec2 texel = vec2(0.002, 0.003);
// 輪廓圖不是每一格都重畫：鏡頭在它畫完之後又移動了多少（畫面比例），取樣時補回來，影子才不會跟著鏡頭抖。
uniform vec2 shift = vec2(0.0);

float covered(vec2 at) {
	vec2 uv = at - shift;
	// 斜對角兩點取樣加上線性過濾：影子的邊緣是柔的，不是鋸齒（輪廓圖本身只有半解析度，兩點就夠）。
	// 用 textureLod：這個函式在迴圈與分支裡被呼叫，那裡算不出取樣層級，明確指定第 0 層最保險。
	float sum = textureLod(silhouette, uv + texel * vec2(-0.8, -0.8), 0.0).a;
	sum += textureLod(silhouette, uv + texel * vec2(0.8, 0.8), 0.0).a;
	return sum * 0.5;
}

void fragment() {
	vec4 lights[MAX_LIGHTS] = {light_0, light_1, light_2, light_3};
	vec4 cones[MAX_LIGHTS] = {cone_0, cone_1, cone_2, cone_3};
	float dark = 0.0;
	// 環境光 0.1 的暗處影子最深，0.5 的亮處剩下六成。
	float contrast = light_dark * mix(1.0, 0.6, smoothstep(0.1, 0.5, ambient));
	for (int i = 0; i < light_count; i++) {
		vec2 offset = SCREEN_UV - lights[i].xy;
		vec2 metric = vec2(offset.x * aspect, offset.y);
		float distance_ratio = length(metric) / max(lights[i].z, 0.0001);
		if (distance_ratio >= 1.0) {
			continue;
		}
		float reach = 1.0 - distance_ratio;
		// 影子的深淺跟著燈的亮度走；光池裡大部分的地方一樣深，只在光池邊緣淡出（燈照不到的地方本來就沒有它的影子）。
		float strength = contrast * lights[i].w * smoothstep(0.0, 0.3, reach);
		if (cones[i].z > 0.0) {
			// 朝某個方向照的燈只在光錐裡有影子；光錐的邊本來就是柔的，影子也在邊緣淡出。
			float across = acos(clamp(dot(normalize(metric + vec2(0.00001)), cones[i].xy), -1.0, 1.0));
			strength *= 1.0 - smoothstep(cones[i].z * 0.8, cones[i].z * 1.5, across);
		}
		if (strength <= 0.004) {
			continue;
		}
		vec2 grow = vec2(1.0) + depth * (1.0 + near_boost * reach);
		vec2 back = offset / grow;
		// 緊貼著光源的東西不算：帶著燈的角色與擺設（槍燈、敵人的眼睛、有燈的擺設）不會被自己的燈投出一大片影子。
		strength *= smoothstep(own_radius, own_radius * 1.8, length(vec2(back.x * aspect, back.y)));
		dark += covered(lights[i].xy + back) * strength;
	}
	COLOR = vec4(vec3(1.0 - min(dark, max_dark)), 1.0);
}
