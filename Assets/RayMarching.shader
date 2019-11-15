Shader "Unlit/RayMarching"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
			#define MAX_STEPS 100
			#define MAX_DIST 100.
			#define SURF_DIST .001

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

			float sdSphere(float3 p, float s)
			{
				return length(p) - s;
			}

			float GetDist(float3 p) {
				float4 s = float4(0, 1, 6, 1);

				float sphereDist = length(p - s.xyz) - s.w;
				return sphereDist;
			}

			float RayMarch(float3 ro, float3 rd) {
				float dO = 0.;

				for (int i = 0; i < MAX_STEPS; i++) {
					float3 p = ro + rd * dO;
					float dS = GetDist(p);
					dO += dS;
					if (dO > MAX_DIST || dS < SURF_DIST) break;
				}

				return dO;
			}

            fixed4 frag (v2f i) : SV_Target
            {
				float2 uv = i.uv - 0.5;
				float3 col = 0;
				float3 ro = float3(0, 2, 0);
				float3 rd = normalize(float3(uv.x - 0.15, uv.y - 0.2, 1));
				
				float d = RayMarch(ro, rd);
				return fixed4(d, d, d, 1);
            }
            ENDCG
        }
    }
}
