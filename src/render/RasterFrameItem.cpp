#include "RasterFrameItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QQuickWindow>
#include <QSGNode>
#include <QSGSimpleTextureNode>
#include <QSGTexture>

namespace {
class RasterFrameRoot final : public QSGNode
{
public:
    RasterFrameRoot()
    {
        imageNode = new QSGSimpleTextureNode;
        imageNode->setOwnsTexture(true);
        appendChildNode(imageNode);
    }

    int revision = -1;
    int geometryRevision = -1;
    QSize size;
    QSGSimpleTextureNode *imageNode = nullptr;
};

QRectF croppedSourceRect(const QImage &image, const QSize &targetSize)
{
    const qreal sourceAspect = qreal(image.width()) / qreal(image.height());
    const qreal targetAspect = qreal(targetSize.width()) / qreal(targetSize.height());
    QRectF sourceRect(image.rect());
    if (sourceAspect > targetAspect) {
        const qreal cropWidth = image.height() * targetAspect;
        sourceRect.setX((image.width() - cropWidth) * 0.5);
        sourceRect.setWidth(cropWidth);
    } else if (sourceAspect < targetAspect) {
        const qreal cropHeight = image.width() / targetAspect;
        sourceRect.setY((image.height() - cropHeight) * 0.5);
        sourceRect.setHeight(cropHeight);
    }
    return sourceRect;
}

QImage renderFrameImage(const QImage &source, const QSize &targetSize, bool circular)
{
    QImage output(targetSize, QImage::Format_ARGB32_Premultiplied);
    output.fill(circular ? Qt::transparent : QColor(16, 23, 34));

    QPainter painter(&output);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    if (circular) {
        QPainterPath path;
        path.addEllipse(QRectF(0, 0, targetSize.width(), targetSize.height()));
        painter.setClipPath(path);
    }
    painter.drawImage(QRectF(0, 0, targetSize.width(), targetSize.height()),
                      source,
                      croppedSourceRect(source, targetSize));
    painter.end();
    return output;
}
} // namespace

RasterFrameItem::RasterFrameItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

RasterFrameItem::~RasterFrameItem() = default;

void RasterFrameItem::setSource(const QUrl &source)
{
    if (m_source == source) {
        return;
    }

    m_source = source;
    emit sourceChanged();
    loadSource();
}

void RasterFrameItem::setCircular(bool circular)
{
    if (m_circular == circular) {
        return;
    }
    m_circular = circular;
    ++m_geometryRevision;
    emit circularChanged();
    update();
}

void RasterFrameItem::loadSource()
{
    ++m_sourceRevision;
    m_image = QImage();

    if (m_source.isEmpty()) {
        setReady(false);
        update();
        return;
    }

    if (!m_source.isLocalFile()) {
        qWarning().noquote() << "[RasterFrameItem] unsupported non-local source" << m_source;
        setReady(false);
        update();
        return;
    }

    const QString path = m_source.toLocalFile();
    if (!QFileInfo::exists(path)) {
        qWarning().noquote() << "[RasterFrameItem] source missing" << path;
        setReady(false);
        update();
        return;
    }

    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        qWarning().noquote() << "[RasterFrameItem] failed to read" << path << reader.errorString();
        setReady(false);
        update();
        return;
    }

    m_image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    qInfo().noquote() << "[RasterFrameItem] loaded" << path << m_image.width() << "x" << m_image.height();
    setReady(true);
    update();
}

void RasterFrameItem::setReady(bool ready)
{
    if (m_ready == ready) {
        return;
    }
    m_ready = ready;
    emit readyChanged();
}

void RasterFrameItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() == oldGeometry.size()) {
        return;
    }
    ++m_geometryRevision;
    update();
}

QSGNode *RasterFrameItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (!m_ready || m_image.isNull() || width() <= 0 || height() <= 0 || !window()) {
        delete oldNode;
        return nullptr;
    }

    const QSize targetSize(qMax(1, int(width())), qMax(1, int(height())));
    auto *root = static_cast<RasterFrameRoot *>(oldNode);
    const bool rebuild = !root
        || root->revision != m_sourceRevision
        || root->geometryRevision != m_geometryRevision
        || root->size != targetSize;
    if (!rebuild) {
        return root;
    }

    delete root;
    root = new RasterFrameRoot;
    root->revision = m_sourceRevision;
    root->geometryRevision = m_geometryRevision;
    root->size = targetSize;

    QSGTexture *texture = window()->createTextureFromImage(renderFrameImage(m_image, targetSize, m_circular));
    if (!texture) {
        delete root;
        return nullptr;
    }

    root->imageNode->setTexture(texture);
    root->imageNode->setFiltering(QSGTexture::Linear);
    root->imageNode->setRect(0, 0, width(), height());
    root->imageNode->markDirty(QSGNode::DirtyGeometry);
    root->imageNode->markDirty(QSGNode::DirtyMaterial);
    return root;
}
