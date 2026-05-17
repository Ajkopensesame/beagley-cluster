#include "NativePanelItem.h"

#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>

namespace {
QSGGeometryNode *createRectNode()
{
    auto *node = new QSGGeometryNode;
    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);

    auto *material = new QSGFlatColorMaterial;
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

void setRect(QSGGeometryNode *node, const QRectF &rect, const QColor &color)
{
    auto *geometry = node->geometry();
    if (rect.width() <= 0 || rect.height() <= 0 || color.alpha() <= 0) {
        geometry->allocate(0);
        node->markDirty(QSGNode::DirtyGeometry);
        return;
    }

    geometry->allocate(6);
    auto *vertices = geometry->vertexDataAsPoint2D();
    const float x0 = float(rect.left());
    const float y0 = float(rect.top());
    const float x1 = float(rect.right());
    const float y1 = float(rect.bottom());

    vertices[0].set(x0, y0);
    vertices[1].set(x1, y0);
    vertices[2].set(x0, y1);
    vertices[3].set(x1, y0);
    vertices[4].set(x1, y1);
    vertices[5].set(x0, y1);

    static_cast<QSGFlatColorMaterial *>(node->material())->setColor(color);
    node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
}

class NativePanelNode final : public QSGNode
{
public:
    NativePanelNode()
    {
        fill = createRectNode();
        top = createRectNode();
        right = createRectNode();
        bottom = createRectNode();
        left = createRectNode();
        appendChildNode(fill);
        appendChildNode(top);
        appendChildNode(right);
        appendChildNode(bottom);
        appendChildNode(left);
    }

    QSGGeometryNode *fill = nullptr;
    QSGGeometryNode *top = nullptr;
    QSGGeometryNode *right = nullptr;
    QSGGeometryNode *bottom = nullptr;
    QSGGeometryNode *left = nullptr;
};
} // namespace

NativePanelItem::NativePanelItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void NativePanelItem::setColor(const QColor &color)
{
    if (m_color == color) {
        return;
    }
    m_color = color;
    emit colorChanged();
    update();
}

void NativePanelItem::setBorderColor(const QColor &color)
{
    if (m_borderColor == color) {
        return;
    }
    m_borderColor = color;
    emit borderColorChanged();
    update();
}

void NativePanelItem::setBorderWidth(qreal borderWidth)
{
    borderWidth = qMax<qreal>(0.0, borderWidth);
    if (qFuzzyCompare(m_borderWidth, borderWidth)) {
        return;
    }
    m_borderWidth = borderWidth;
    emit borderWidthChanged();
    update();
}

void NativePanelItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        update();
    }
}

QSGNode *NativePanelItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (width() <= 0 || height() <= 0) {
        delete oldNode;
        return nullptr;
    }

    auto *root = static_cast<NativePanelNode *>(oldNode);
    if (!root) {
        root = new NativePanelNode;
    }

    const QRectF bounds(0.0, 0.0, width(), height());
    const qreal border = qMin(m_borderWidth, qMin(width(), height()) / 2.0);
    setRect(root->fill, bounds, m_color);
    setRect(root->top, QRectF(0.0, 0.0, width(), border), m_borderColor);
    setRect(root->right, QRectF(width() - border, 0.0, border, height()), m_borderColor);
    setRect(root->bottom, QRectF(0.0, height() - border, width(), border), m_borderColor);
    setRect(root->left, QRectF(0.0, 0.0, border, height()), m_borderColor);
    return root;
}
