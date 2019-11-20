using UnityEngine;

public class AutoRotating : MonoBehaviour
{
    [SerializeField] private Vector3 m_rotateEulers = Vector3.up;
    [SerializeField] private float m_rotateSpeed = 180f;
    private Transform m_transform;

    private void Awake()
    {
        m_transform = transform;
    }

    private void Update()
    {
        m_transform.Rotate(m_rotateEulers * m_rotateSpeed * Time.deltaTime);
    }
}
