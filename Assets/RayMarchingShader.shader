
Shader "Unlit/RayMarchingShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Cull Off
		ZWrite Off
		ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma target 3.0

            #include "UnityCG.cginc"
			#define SPHERE_COUNT 25

			sampler2D _MainTex;
			float4 _MainTex_ST;

			//Setup
			uniform sampler2D _CameraDepthTexture;
			uniform float4x4 _CameraFrustumPlanes;
			uniform float4x4 _CameraToWorldMatrix;
			uniform float _MaxDistance;
			uniform int _MaxIterations;
			uniform float _Accuracy;

			//Color
			uniform float4 _MainColor;

			//Light
			uniform float3 _LightDir;
			uniform float3 _LightCol;
			uniform float _LightIntensity;

			//Shadow
			uniform float2 _ShadowDistance;
			uniform float _ShadowIntensity;
			uniform float _ShadowPenumbra;

			//Ambient Occlusion
			uniform float _AOStepSize;
			uniform int _AOIterations;
			uniform float _AOIntensity;

			//Reflection
			uniform int _ReflectionCount;
			uniform float _ReflectionIntensity;
			uniform float _EnvironmentReflectionIntensity;
			uniform samplerCUBE _ReflectionCube;

			//SDF
			uniform float _Smooth;
			uniform float3 _GroundPosition;
			uniform float3 _GroundColor;
			uniform float3 _SphereColors[SPHERE_COUNT];

            struct a2v
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
				float3 ray : TEXCOORD1;
            };

            v2f vert (a2v v)
            {
                v2f o;

				half index = v.vertex.z;
				v.vertex.z = 0;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				o.ray = _CameraFrustumPlanes[(int)index].xyz;
				o.ray /= abs(o.ray.z);
				o.ray = mul(_CameraToWorldMatrix, o.ray);

                return o;
            }

			float sdPlane(float3 p)
			{
				return p.y;
			}

			// Distance from p to sphere of radius s (centered at origin)
			float sdSphere(float3 p, float s)
			{
				return length(p) - s;
			}

			// Distance from p to box whose half-dimensions are b.x, b.y, b.z
			float sdBox(float3 p, float3 b)
			{
				float3 d = abs(p) - b;
				return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
			}

			// Distance from p to ellipsoid the length of whose semi-principal axes is r.x, r.y, r.z
			float sdEllipsoid(in float3 p, in float3 r)
			{
				return (length(p / r) - 1.0) * min(min(r.x, r.y), r.z);
			}

			// Distance from p to box of half-dimensions b.x,y,z plus buffer radius r
			float sdRoundBox(float3 p, float3 b, float r)
			{
				return length(max(abs(p) - b, 0.0)) - r;
			}

			// Distance from p to horizontal torus with major radius t.x and minor radius t.y
			float sdTorus(float3 p, float2 t)
			{
				return length(float2(length(p.xz) - t.x, p.y)) - t.y;
			}

			float sdHexPrism(float3 p, float2 h)
			{
				float3 q = abs(p);
#if 0
				return max(q.z - h.y, max((q.x*0.866025 + q.y*0.5), q.y) - h.x);
#else
				float d1 = q.z - h.y;
				float d2 = max((q.x*0.866025 + q.y*0.5), q.y) - h.x;
				return length(max(float2(d1, d2), 0.0)) + min(max(d1, d2), 0.);
#endif
			}

			// Distance from p to cylinder of radius r with spherical ends centered at a and b.
			// This is a rare exception to the rule that all primitives are centered at the origin.
			float sdCapsule(float3 p, float3 a, float3 b, float r)
			{
				float3 pa = p - a, ba = b - a;
				float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
				return length(pa - ba * h) - r;
			}

			float sdTriPrism(float3 p, float2 h)
			{
				float3 q = abs(p);
#if 0
				return max(q.z - h.y, max(q.x*0.866025 + p.y*0.5, -p.y) - h.x*0.5);
#else
				float d1 = q.z - h.y;
				float d2 = max(q.x*0.866025 + p.y*0.5, -p.y) - h.x*0.5;
				return length(max(float2(d1, d2), 0.0)) + min(max(d1, d2), 0.);
#endif
			}

			// Distance from p to cylinder with radius h.x and half-length h.y.
			float sdCylinder(float3 p, float2 h)
			{
				float2 d = abs(float2(length(p.xz), p.y)) - h;
				return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
			}

			// Distance from p to a cone of height c.z whose vertex is at the origin
			// and is pointing up.
			float sdCone(in float3 p, in float3 c)
			{
				float2 q = float2(length(p.xz), p.y);
				float d1 = -q.y - c.z;
				float d2 = max(dot(q, c.xy), q.y);
				return length(max(float2(d1, d2), 0.0)) + min(max(d1, d2), 0.);
			}

			float sdConeSection(in float3 p, in float h, in float r1, in float r2)
			{
				float d1 = -p.y - h;
				float q = p.y - h;
				float si = 0.5*(r1 - r2) / h;
				float d2 = max(sqrt(dot(p.xz, p.xz)*(1.0 - si * si)) + q * si - r2, q);
				return length(max(float2(d1, d2), 0.0)) + min(max(d1, d2), 0.);
			}

			float sdPryamid4(float3 p, float3 h) // h = { cos a, sin a, height }
			{
				// Tetrahedron = Octahedron - Cube
				float box = sdBox(p - float3(0, -2.0  *h.z, 0), float3(2.0 * h.z, 2.0 * h.z, 2.0 * h.z));

				float d = 0.0;
				d = max(d, abs(dot(p, float3(-h.x, h.y, 0))));
				d = max(d, abs(dot(p, float3(h.x, h.y, 0))));
				d = max(d, abs(dot(p, float3(0, h.y, h.x))));
				d = max(d, abs(dot(p, float3(0, h.y, -h.x))));
				float octa = d - h.z;
				return max(-box, octa); // Subtraction
			}

			// Euclidean distance function (same as builtin length(p)?)
			float length2(float2 p)
			{
				return sqrt(p.x*p.x + p.y*p.y);
			}

			// Non-Euclidean distance function, so the sphere "length6(p) = k" is squarish.
			float length6(float2 p)
			{
				p = p * p*p; p = p * p;
				return pow(p.x + p.y, 1.0 / 6.0);
			}

			// Non-Euclidean distance function, so the sphere "length8(p) = k" is more squarish.
			float length8(float2 p)
			{
				p = p * p; p = p * p; p = p * p;
				return pow(p.x + p.y, 1.0 / 8.0);
			}

			// A torus with a squarish minor cross section, using non-Euclidean distance function.
			float sdTorus82(float3 p, float2 t)
			{
				float2 q = float2(length2(p.xz) - t.x, p.y);
				return length8(q) - t.y;
			}

			// A torus with squarish major and minor cross sections, using non-Euclidean distance function.
			float sdTorus88(float3 p, float2 t)
			{
				float2 q = float2(length8(p.xz) - t.x, p.y);
				return length8(q) - t.y;
			}

			// a cylinder with squarish horizontal cross-section, with radius h.x and half-length h.y.
			float sdCylinder6(float3 p, float2 h)
			{
				return max(length6(p.xz) - h.x, abs(p.y) - h.y);
			}

			float sdOctahedron(float3 p, float s)
			{
				p = abs(p);
				return (p.x + p.y + p.z - s)*0.57735027;
			}

			float opUnion(float d1, float d2)
			{
				return min(d1, d2);
			}

			float opSubtraction(float d1, float d2) { return max(-d1, d2); }

			float opIntersection(float d1, float d2) { return max(d1, d2); }

			float4 opSmoothUnion(float4 d1, float4 d2, float k) {
				float h = clamp(0.5 + 0.5*(d2.w - d1.w) / k, 0.0, 1.0);
				float3 color = lerp(d2.rgb, d1.rgb, h);
				float dist = lerp(d2.w, d1.w, h) - k * h*(1.0 - h);
				return float4(color, dist);
			}

			float opSmoothSubtraction(float d1, float d2, float k) {
				float h = clamp(0.5 - 0.5*(d2 + d1) / k, 0.0, 1.0);
				return lerp(d2, -d1, h) + k * h*(1.0 - h);
			}

			float opSmoothIntersection(float d1, float d2, float k) {
				float h = clamp(0.5 - 0.5*(d2 - d1) / k, 0.0, 1.0);
				return lerp(d2, d1, h) + k * h*(1.0 - h);
			}

			float3 opRep(float3 p, float3 c)
			{
				return fmod(p, c) - 0.5 * c;
			}

			float3 opTwist(float3 p)
			{
				float  c = cos(10.0*p.y + 10.0);
				float  s = sin(10.0*p.y + 10.0);
				float2x2   m = float2x2(c, -s, s, c);
				return float3(mul(m, p.xz), p.y);
			}

			float3 opCheapBend(float3 p)
			{
				float c = cos(20.0 * p.y);
				float s = sin(20.0 * p.y);
				float2x2  m = float2x2(c, -s, s, c);
				return float3(mul(m, p.xy), p.z);
			}

			float opBlend(float d1, float d2) {
				const float k = 0.1;
				float h = clamp(0.5 + 0.5*(d2 - d1) / k, 0.0, 1.0);
				return lerp(d2, d1, h) - k * h*(1.0 - h);
			}

			float4 distanceField(float3 pos)
			{
				float3 color = _SphereColors[0];
				float sd = sdSphere(pos - float3(0.0, 0.25, 0.0), 0.25);
				float4 result = float4(color, sd);

				color = _SphereColors[1];
				sd = sdBox(pos - float3(1.0, 0.25, 0.0), float3(0.25, 0.25, 0.25));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[2];
				sd = sdRoundBox(pos - float3(1.0, 0.25, 1.0), float3(0.15, 0.15, 0.15), 0.1);
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[3];
				sd = sdTorus(pos - float3(0.0, 0.25, 1.0), float2(0.20, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[4];
				sd = sdCapsule(pos, float3(-1.3, 0.10, -0.1), float3(-0.8, 0.50, 0.2), 0.1);
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[5];
				sd = sdTriPrism(pos - float3(-1.0, 0.25, -1.0), float2(0.25, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[6];
				sd = sdCylinder(pos - float3(1.0, 0.30, -1.0), float2(0.1, 0.2));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[7];
				sd = sdCone(pos - float3(0.0, 0.50, -1.0), float3(0.8, 0.6, 0.3));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[8];
				sd = sdTorus82(pos - float3(0.0, 0.25, 2.0), float2(0.20, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[9];
				sd = sdTorus88(pos - float3(-1.0, 0.25, 2.0), float2(0.20, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[10];
				sd = sdCylinder6(pos - float3(1.0, 0.30, 2.0), float2(0.1, 0.2));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[11];
				sd = sdHexPrism(pos - float3(-1.0, 0.20, 1.0), float2(0.25, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[12];
				sd = sdPryamid4(pos - float3(-1.0, 0.15, -2.0), float3(0.8, 0.6, 0.25));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[13];
				sd = opIntersection(sdBox(pos - float3(2.0, 0.2, 1.0), float3(0.20, 0.20, 0.20)),
					sdSphere(pos - float3(2.0, 0.2, 1.0), 0.25));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[14];
				sd = opSubtraction(sdSphere(pos - float3(-2.0, 0.2, 1.0), 0.25),
					sdRoundBox(pos - float3(-2.0, 0.2, 1.0), float3(0.15, 0.15, 0.15), 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[15];
				sd = opSubtraction(sdCylinder(opRep(float3(atan2(pos.x + 2.0, pos.z) / 6.2831, pos.y, 0.02 + 0.5 * length(pos - float3(-2.0, 0.2, 0.0))), float3(0.05, 1.0, 0.05)), float2(0.02, 0.6)),
					sdTorus82(pos - float3(-2.0, 0.2, 0.0), float2(0.20, 0.1)));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[16];
				sd = 0.5 * sdSphere(pos - float3(-2.0, 0.25, -1.0), 0.2)
					+ 0.03 * sin(50.0 * pos.x) * sin(50.0 * pos.y) * sin(50.0 * pos.z);
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[17];
				sd = 0.5 * sdTorus(opTwist(pos - float3(-2.0, 0.25, 2.0)), float2(0.20, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[18];
				sd = 0.3 * sdTorus(opCheapBend(pos - float3(2.0, 0.25, -1.0)), float2(0.20, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[19];
				sd = sdConeSection(pos - float3(0.0, 0.35, -2.0), 0.15, 0.2, 0.1);
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[20];
				sd = sdEllipsoid(pos - float3(1.0, 0.35, -2.0), float3(0.15, 0.2, 0.05));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[21];
				sd = sdOctahedron(pos - float3(-2.0, 0.25, -2.0), 0.2);
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[22];
				sd = opBlend(sdBox(pos - float3(2.0, 0.25, 0.0), float3(.15, .05, .15)),
					sdCylinder(pos - float3(2.0, 0.25, 0.0), float2(0.04, 0.2)));
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[23];
				sd = sdSphere(pos - float3(2.0, 0.25, -2.0), 0.1);
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0, 0.45, -2.0), 0.1), 0.05).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0, 0.05, -2.0), 0.1), 0.05).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(1.8, 0.25, -2.0), 0.1), 0.05).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.2, 0.25, -2.0), 0.1), 0.05).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0, 0.25, -2.2), 0.1), 0.05).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0, 0.25, -1.8), 0.1), 0.05).w;
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				color = _SphereColors[24];
				sd = sdSphere(pos - float3(2.0 + sin(_Time.y) * 0.25, 0.25 + sin(_Time.y) * 0.25, 2.0), 0.1);
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 + sin(_Time.y) * 0.25, 0.25 - sin(_Time.y) * 0.25, 2.0), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 + sin(_Time.y) * 0.25, 0.25, 2.0 + sin(_Time.y) * 0.25), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 + sin(_Time.y) * 0.25, 0.25, 2.0 - sin(_Time.y) * 0.25), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 - sin(_Time.y) * 0.25, 0.25 + sin(_Time.y) * 0.25, 2.0), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 - sin(_Time.y) * 0.25, 0.25 - sin(_Time.y) * 0.25, 2.0), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 - sin(_Time.y) * 0.25, 0.25, 2.0 + sin(_Time.y) * 0.25), 0.1), 0.1).w;
				sd = opSmoothUnion(sd, sdSphere(pos - float3(2.0 - sin(_Time.y) * 0.25, 0.25, 2.0 - sin(_Time.y) * 0.25), 0.1), 0.1).w;
				result = opSmoothUnion(result, float4(color, sd), _Smooth);

				sd = sdPlane(pos - _GroundPosition);
				float4 ground = float4(_GroundColor, sd);
				return opSmoothUnion(result, ground, _Smooth);
			}

			float3 getNormal(float3 p)
			{
				const float2 offset = float2(0.001, 0);
				float3 normal = float3(
					distanceField(p + offset.xyy).w - distanceField(p - offset.xyy).w,
					distanceField(p + offset.yxy).w - distanceField(p - offset.yxy).w,
					distanceField(p + offset.yyx).w - distanceField(p - offset.yyx).w
					);

				return normalize(normal);
			}

			float hardShadow(float3 ro, float3 rd, float mint, float maxt)
			{
				for (float t = mint; t < maxt;)
				{
					float h = distanceField(ro + rd * t).w;
					if (h < 0.001)
					{
						return 0.0;
					}
					
					t += h;
				}

				return 1.0;
			}

			float solfShadow(float3 ro, float3 rd, float mint, float maxt, float k)
			{
				float result = 1.0;

				for (float t = mint; t < maxt;)
				{
					float h = distanceField(ro + rd * t).w;
					if (h < 0.001)
					{
						return 0.0;
					}

					result = min(result, k * h / t);
					t += h;
				}

				return result;
			}

			float getAmbientOcclusion(float3 p, float3 n)
			{
				float step = _AOStepSize;
				float ao = 0.0;
				float dist;
				for (int i = 0; i < _AOIterations; i++)
				{
					dist = step * i;
					ao += max(0.0, (dist - distanceField(p + n * dist)) / dist).w;
				}

				return 1.0 - ao * _AOIntensity;
			}

			float3 getShading(float3 p, float3 n, float3 c)
			{
				float3 result;

				//Diffuse Color
				float3 color = c;

				//Directional Light
				float light = (_LightCol * dot(-_LightDir, n) * 0.5 + 0.5) * _LightIntensity;

				//Shadows
				float shadow = solfShadow(p, -_LightDir, _ShadowDistance.x, _ShadowDistance.y, _ShadowPenumbra) * 0.5 + 0.5;
				shadow = max(0.0, pow(shadow, _ShadowIntensity));

				//Ambient Occlusion
				float ao = getAmbientOcclusion(p, n);

				result = color * light * shadow * ao;

				return result;
			}

			bool raymarching(float3 rayOrigin, float3 rayDirection, int maxIterations, float maxDistance, float depth, inout float3 p, inout float3 dCol)
			{
				bool hit;
				float t = 0; //distance travelled along the ray direction

				for (int i = 0; i < maxIterations; i++)
				{
					if (t > maxDistance || t >= depth)
					{
						hit = false;
						break;
					}

					p = rayOrigin + rayDirection * t;
					float4 d = distanceField(p);
					if (d.w < _Accuracy) //hit something
					{
						hit = true;
						dCol = d.rgb;
						break;
					}

					t += d.w;
				}

				return hit;
			}

            float4 frag (v2f i) : SV_Target
            {
				float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
				depth *= length(i.ray);
				float3 col = tex2D(_MainTex, i.uv);
				float3 rayDirection = normalize(i.ray);
				float3 rayOrigin = _WorldSpaceCameraPos;

				float4 result;
				float3 hitPosition;
				float3 dCol;
				bool hit = raymarching(rayOrigin, rayDirection, _MaxIterations, _MaxDistance, depth, hitPosition, dCol);
				if (hit)
				{
					//shading
					float3 normal = getNormal(hitPosition);
					float3 shading = getShading(hitPosition, normal, dCol);
					result = float4(shading, 1);

					if (_EnvironmentReflectionIntensity * _ReflectionIntensity != 0)
					{
						result += float4(texCUBE(_ReflectionCube, normal).rgb * _EnvironmentReflectionIntensity * _ReflectionIntensity, 0);
					}

					//Reflection
					if (_ReflectionCount > 0)
					{
						int maxIterations = _MaxIterations;
						float maxDistance = _MaxDistance;

						for (int x = 0; x < _ReflectionCount; x++)
						{
							maxIterations *= 0.5;
							maxDistance *= 0.5;

							rayDirection = normalize(reflect(rayDirection, normal));
							rayOrigin = hitPosition + (rayDirection * 0.01);
							hit = raymarching(rayOrigin, rayDirection, maxIterations, maxDistance, _MaxDistance, hitPosition, dCol);

							if (hit)
							{
								normal = getNormal(hitPosition);
								shading = getShading(hitPosition, normal, dCol);
								result += float4(shading * _ReflectionIntensity, 0);
							}
							else
							{
								break;
							}
						}
					}
				}
				else
				{
					//Environment
					result = float4(rayDirection, 0);
				}

				col = col * (1 - result.w) + result.xyz * result.w;
				return float4(col, 1);
            }
            ENDCG
        }
    }
}
