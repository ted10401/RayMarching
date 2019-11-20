using System.Collections.Generic;
using UnityEngine;

[RequireComponent(typeof(Camera))]
[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class RayMarchingCamera : MonoBehaviour
{
    [SerializeField] private Shader m_shader = null;

    public Material material
    {
        get
        {
            if(m_material == null && m_shader != null)
            {
                m_material = new Material(m_shader);
                m_material.hideFlags = HideFlags.HideAndDontSave;
            }

            return m_material;
        }
    }
    private Material m_material;

    public Camera myCamera
    {
        get
        {
            if(m_camera == null)
            {
                m_camera = GetComponent<Camera>();
            }

            return m_camera;
        }
    }
    private Camera m_camera;

    [Header("Setup")]
    [SerializeField, Range(1f, 1000f)] private float m_maxDistance = 10;
    [SerializeField, Range(1, 1000)] private int m_maxIterations = 164;
    [SerializeField, Range(0.001f, 0.1f)] private float m_accuracy = 0.01f;

    [Header("Color")]
    [SerializeField] private Color m_mainColor = Color.white;

    [Header("Light")]
    [SerializeField] private Transform m_lightTransform = null;
    [SerializeField] private Color m_lightColor = Color.white;
    [SerializeField] private float m_lightIntensity = 1f;

    [Header("Shadow")]
    [SerializeField] private Vector2 m_shadowDistance = new Vector2(0.01f, 10f);
    [SerializeField] private float m_shadowIntensity = 1f;
    [SerializeField] private float _shadowPenumbra = 75f;

    [Header("Ambient Occlusion")]
    [SerializeField, Range(0.01f, 10.0f)] private float m_ambientOcclusionStepSize = 0.1f;
    [SerializeField, Range(1, 5)] private int m_ambientOcclusionIterations = 3;
    [SerializeField, Range(0f, 1f)] private float m_ambientOcclusionIntensity = 0.25f;

    [Header("Reflection")]
    [SerializeField, Range(0, 10)] private int m_reflectionCount = 0;
    [SerializeField, Range(0f, 1f)] private float m_reflectionIntensity = 0;
    [SerializeField, Range(0f, 1f)] private float m_environmentReflectionIntensity = 0;
    [SerializeField] private Cubemap m_reflectionCube = null;

    private const int SPHERE_COUNT = 16;

    [Header("Signed Distance Field")]
    [SerializeField] private float m_smooth = 0f;
    [SerializeField] private Vector3 m_groundPosition = new Vector3(0, 0, 0);
    [SerializeField] private Color m_groundColor = Color.white;
    [SerializeField] private Gradient m_sphereGradient = new Gradient();
    private Color[] m_colors = new Color[25];

    private void OnEnable()
    {
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = 9999;
        myCamera.depthTextureMode = DepthTextureMode.Depth;
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if(material == null)
        {
            Graphics.Blit(source, destination);
            return;
        }

        //Setup
        material.SetMatrix("_CameraFrustumPlanes", GetCameraFrustumPlanes());
        material.SetMatrix("_CameraToWorldMatrix", myCamera.cameraToWorldMatrix);
        material.SetFloat("_MaxDistance", m_maxDistance);
        material.SetInt("_MaxIterations", m_maxIterations);
        material.SetFloat("_Accuracy", m_accuracy);

        //Color
        material.SetColor("_MainColor", m_mainColor);

        //Light
        material.SetVector("_LightDir", m_lightTransform.forward);
        material.SetColor("_LightCol", m_lightColor);
        material.SetFloat("_LightIntensity", m_lightIntensity);

        //Shadow
        material.SetVector("_ShadowDistance", m_shadowDistance);
        material.SetFloat("_ShadowIntensity", m_shadowIntensity);
        material.SetFloat("_ShadowPenumbra", _shadowPenumbra);

        //Ambient Occlusion
        material.SetFloat("_AOStepSize", m_ambientOcclusionStepSize);
        material.SetInt("_AOIterations", m_ambientOcclusionIterations);
        material.SetFloat("_AOIntensity", m_ambientOcclusionIntensity);

        //Reflection
        material.SetInt("_ReflectionCount", m_reflectionCount);
        material.SetFloat("_ReflectionIntensity", m_reflectionIntensity);
        material.SetFloat("_EnvironmentReflectionIntensity", m_environmentReflectionIntensity);
        material.SetTexture("_ReflectionCube", m_reflectionCube);

        //SDF
        material.SetFloat("_Smooth", m_smooth);
        material.SetVector("_GroundPosition", m_groundPosition);
        material.SetVector("_GroundColor", m_groundColor);

        for(int i = 0; i < m_colors.Length; i++)
        {
            m_colors[i] = m_sphereGradient.Evaluate(i * 1f / (m_colors.Length - 1));
        }
        material.SetColorArray("_SphereColors", m_colors);

        RenderTexture.active = destination;
        material.SetTexture("_MainTex", source);
        GL.PushMatrix();
        GL.LoadOrtho();
        material.SetPass(0);
        GL.Begin(GL.QUADS);

        //BL
        GL.MultiTexCoord2(0, 0, 0);
        GL.Vertex3(0, 0, 3);
        //BR
        GL.MultiTexCoord2(0, 1, 0);
        GL.Vertex3(1, 0, 2);
        //TR
        GL.MultiTexCoord2(0, 1, 1);
        GL.Vertex3(1, 1, 1);
        //TL
        GL.MultiTexCoord2(0, 0, 1);
        GL.Vertex3(0, 1, 0);

        GL.End();
        GL.PopMatrix();
    }

    private Matrix4x4 GetCameraFrustumPlanes()
    {
        float fov = Mathf.Tan(myCamera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        Vector3 up = Vector3.up * fov;
        Vector3 right = Vector3.right * fov * myCamera.aspect;
        Vector3 topLeft = -Vector3.forward + up - right;
        Vector3 topRight = -Vector3.forward + up + right;
        Vector3 bottomLeft = -Vector3.forward - up - right;
        Vector3 bottomRight = -Vector3.forward - up + right;

        Matrix4x4 matrix4X = Matrix4x4.identity;
        matrix4X.SetRow(0, topLeft);
        matrix4X.SetRow(1, topRight);
        matrix4X.SetRow(2, bottomRight);
        matrix4X.SetRow(3, bottomLeft);
        return matrix4X;
    }
}
