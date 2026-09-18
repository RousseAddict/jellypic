import UIKit

protocol ZoomTransitionEndpoint: AnyObject {
    func zoomTransitionImage() -> UIImage?
    func zoomTransitionRect(in container: UIView) -> CGRect?
    func zoomTransitionSetHidden(_ hidden: Bool)
}

final class ZoomTransition: NSObject, UIViewControllerAnimatedTransitioning {

    private let isPresenting: Bool
    private weak var source: ZoomTransitionEndpoint?
    private weak var destination: ZoomTransitionEndpoint?

    init(presenting: Bool,
         source: ZoomTransitionEndpoint?,
         destination: ZoomTransitionEndpoint?) {
        self.isPresenting = presenting
        self.source = source
        self.destination = destination
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        return isPresenting ? 0.34 : 0.3
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView
        let duration = transitionDuration(using: context)

        let viewerView: UIView?
        if isPresenting, let toView = context.view(forKey: .to) {
            toView.frame = container.bounds
            toView.alpha = 0
            container.addSubview(toView)
            toView.layoutIfNeeded()
            viewerView = toView
        } else {
            viewerView = context.view(forKey: .from)
        }

        guard let image = source?.zoomTransitionImage(),
              let start = source?.zoomTransitionRect(in: container),
              let end = destination?.zoomTransitionRect(in: container) else {
            UIView.animate(withDuration: duration,
                           animations: { viewerView?.alpha = self.isPresenting ? 1 : 0 },
                           completion: { _ in context.completeTransition(true) })
            return
        }

        let travelling = UIImageView(image: image)
        travelling.contentMode = .scaleAspectFill
        travelling.clipsToBounds = true
        travelling.frame = start
        container.addSubview(travelling)

        source?.zoomTransitionSetHidden(true)
        destination?.zoomTransitionSetHidden(true)

        UIView.animate(withDuration: duration,
                       delay: 0,
                       usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        viewerView?.alpha = self.isPresenting ? 1 : 0
                        travelling.frame = end
                       },
                       completion: { _ in
                        travelling.removeFromSuperview()
                        self.source?.zoomTransitionSetHidden(false)
                        self.destination?.zoomTransitionSetHidden(false)
                        context.completeTransition(true)
                       })
    }
}
