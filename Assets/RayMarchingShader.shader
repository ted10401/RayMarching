
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
			uniform float3 _SpherePosition;
			uniform float _SphereRadius;
			uniform float3 _BoxPosition;
			uniform float3 _BoxScale;
			uniform float3 _RoundBoxPosition;
			uniform float3 _RoundBoxScale;
			uniform float _RoundBoxRadius;
			uniform float3 _TorusPosition;
			uniform float2 _TorusRadius;

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

			float sdPlane(float3 position, float3 center, float4 normal)
			{
				float3 p = position - center;
				return dot(p, normal.xyz) + normal.w;
			}

			float sdSphere(float3 position, float3 center, float radius)
			{
				return length(position - center) - radius;
			}

			float sdBox(float3 position, float3 center, float3 scale)
			{
				float3 p = position - center;
				float3 q = abs(p) - scale;
				return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
			}

			float sdRoundBox(float3 position, float3 center, float3 scale, float r)
			{
				float3 p = position - center;
				float3 q = abs(p) - scale;
				return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
			}

			float sdTorus(float3 position, float3 center, float2 radius)
			{
				float3 p = position - center;
				float2 q = float2(length(p.xz) - radius.x, p.y);
				return length(q) - radius.y;
			}

			float opUnion(float d1, float d2) { return min(d1, d2); }

			float opSubtraction(float d1, float d2) { return max(-d1, d2); }

			float opIntersection(float d1, float d2) { return max(d1, d2); }

			float opSmoothUnion(float d1, float d2, float k) {
				float h = clamp(0.5 + 0.5*(d2 - d1) / k, 0.0, 1.0);
				return lerp(d2, d1, h) - k * h*(1.0 - h);
			}

			float opSmoothSubtraction(float d1, float d2, float k) {
				float h = clamp(0.5 - 0.5*(d2 + d1) / k, 0.0, 1.0);
				return lerp(d2, -d1, h) + k * h*(1.0 - h);
			}

			float opSmoothIntersection(float d1, float d2, float k) {
				float h = clamp(0.5 - 0.5*(d2 - d1) / k, 0.0, 1.0);
				return lerp(d2, d1, h) + k * h*(1.0 - h);
			}

			float distanceField(float3 p)
			{
				float plane = sdPlane(p, float3(0, 0, 0), float4(0, 1, 0, 0));
				float sphere = sdSphere(p, _SpherePosition, _SphereRadius);
				float box = sdBox(p, _BoxPosition, _BoxScale);
				float roundBox = sdRoundBox(p, _RoundBoxPosition, _RoundBoxScale, _RoundBoxRadius);
				float torus = sdTorus(p, _TorusPosition, _TorusRadius);

				/*float sd = sphere;
				sd = opSmoothUnion(sd, box, _Smooth);
				sd = opSmoothUnion(sd, roundBox, _Smooth);
				sd = opSmoothUnion(sd, torus, _Smooth);*/

				float sd = opSmoothSubtraction(sphere, roundBox, _Smooth);

				return opUnion(plane, sd);
			}

			float3 getNormal(float3 p)
			{
				const float2 offset = float2(0.001, 0);
				float3 normal = float3(
					distanceField(p + offset.xyy) - distanceField(p - offset.xyy),
					distanceField(p + offset.yxy) - distanceField(p - offset.yxy),
					distanceField(p + offset.yyx) - distanceField(p - offset.yyx)
					);

				return normalize(normal);
			}

			float hardShadow(float3 ro, float3 rd, float mint, float maxt)
			{
				for (float t = mint; t < maxt;)
				{
					float h = distanceField(ro + rd * t);
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
					float h = distanceField(ro + rd * t);
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
				for (int i = 1; i <= _AOIterations; i++)
				{
					dist = step * i;
					ao += max(0.0, (dist - distanceField(p + n * dist)) / dist);
				}

				return 1.0 - ao * _AOIntensity;
			}

			float3 getShading(float3 p, float3 n)
			{
				float3 result;

				//Diffuse Color
				float3 color = _MainColor;

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

			float4 raymarching(float3 rayOrigin, float3 rayDirection, float depth)
			{
				float4 result = float4(1, 1, 1, 1);
				const int max_iteration = _MaxDistance;
				float t = 0; //distance travelled along the ray direction

				for (int i = 0; i < max_iteration; i++)
				{
					if (t > _MaxDistance || t >= depth)
					{
						//Environment
						result = float4(rayDirection, 0);
						break;
					}

					float3 p = rayOrigin + rayDirection * t;
					float d = distanceField(p);
					if (d < _Accuracy) //hit something
					{
						//shading
						float3 normal = getNormal(p);
						float3 shading = getShading(p, normal);
						result = float4(shading, 1);

						break;
					}

					t += d;
				}

				return result;
			}

            float4 frag (v2f i) : SV_Target
            {
				float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
				depth *= length(i.ray);
				float3 col = tex2D(_MainTex, i.uv);
				float3 rayDirection = normalize(i.ray);
				float3 rayOrigin = _WorldSpaceCameraPos;
				float4 result = raymarching(rayOrigin, rayDirection, depth);

				col = col * (1 - result.w) + result.xyz * result.w;
				return float4(col, 1);
            }
            ENDCG
        }
    }
}
