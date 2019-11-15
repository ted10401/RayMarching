using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class RayMarching : MonoBehaviour
{
    [SerializeField] private Material m_material;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!m_material)
        {
            Graphics.Blit(source, destination);
            return;
        }

        m_material.SetMatrix("_FrustumCornersRay", CamFrustum(Camera.main));

        Graphics.Blit(source, destination, m_material);
    }

    private Matrix4x4 CamFrustum(Camera cam)
    {
        Matrix4x4 frustum = Matrix4x4.identity;
        float fov = Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad);
        Vector3 goUp = Vector3.up * fov;
        Vector3 goRight = Vector3.right * fov * cam.aspect;

        Vector3 TL = (-Vector3.forward - goRight + goUp);
        Vector3 TR = (-Vector3.forward + goRight + goUp);
        Vector3 BR = (-Vector3.forward + goRight - goUp);
        Vector3 BL = (-Vector3.forward - goRight - goUp);

        frustum.SetRow(0, TL);
        frustum.SetRow(1, TR);
        frustum.SetRow(2, BR);
        frustum.SetRow(3, BL);
        return frustum;
    }
}
