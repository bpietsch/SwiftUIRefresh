import SwiftUI
import Foundation
import Introspect

private struct PullToRefresh: UIViewRepresentable {
    
    @Binding var isShowing: Bool
	let willBeginDragging: () -> Void
	let didEndDragging: (Bool) -> Void
    let onRefresh: () -> Void
    
    public init(
        isShowing: Binding<Bool>,
		willBeginDragging: @escaping () -> Void,
		didEndDragging: @escaping (Bool) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        _isShowing = isShowing
		self.willBeginDragging = willBeginDragging
		self.didEndDragging = didEndDragging
        self.onRefresh = onRefresh
    }
    
    public class Coordinator {
        let onRefresh: () -> Void
        let isShowing: Binding<Bool>
        
        init(
            onRefresh: @escaping () -> Void,
            isShowing: Binding<Bool>
        ) {
            self.onRefresh = onRefresh
            self.isShowing = isShowing
        }
        
        @objc
        func onValueChanged() {
            isShowing.wrappedValue = true
            onRefresh()
        }
    }
	
	private func registerScrollViewDelegates( onObject object: Any,
						willBeginDragging willBeginClosure: @escaping (_ scrollView: UIScrollView) -> Void,
						didEndDragging didEndClosure: @escaping (_ scrollView: UIScrollView, _ decelerate: Bool) -> Void )
	{
		let superClass: AnyClass = object_getClass(object)!
		let newSubclassName = "PullToRefresh_\(String(cString: class_getName(superClass)))"
		let scrollViewDelegateProtocol = objc_getProtocol("UIScrollViewDelegate")
		let willBeginDraggingSelector = #selector(UIScrollViewDelegate.scrollViewWillBeginDragging(_:))
		let didEndDraggingSelector = #selector(UIScrollViewDelegate.scrollViewDidEndDragging(_:willDecelerate:))
		let willBeginDraggingMethodDescription = protocol_getMethodDescription(scrollViewDelegateProtocol!, willBeginDraggingSelector, false, true)
		let didEndDraggingMethodDescription = protocol_getMethodDescription(scrollViewDelegateProtocol!, didEndDraggingSelector, false, true)
		
		var newSubclass: AnyClass? = objc_allocateClassPair(superClass, newSubclassName, 0)
		if newSubclass != nil {
			let superDidEndMethod = class_getInstanceMethod(superClass, didEndDraggingSelector)
			let newDidEndImplmentationBlock: @convention(block) (AnyObject, UIScrollView, Bool) -> Void =
			{ (self: AnyObject, scrollView: UIScrollView, decelerate: Bool) in
				if superDidEndMethod != nil {
					typealias Function = @convention(c) (AnyObject, Selector) -> Void
					unsafeBitCast(method_getImplementation(superDidEndMethod!), to: Function.self)(self, didEndDraggingSelector)
				}
				
				if objc_getAssociatedObject(self, (newSubclassName as NSString).utf8String!) != nil {
					didEndClosure(scrollView, decelerate)
				}
			}
			
			let superWillBeginMethod = class_getInstanceMethod(superClass, willBeginDraggingSelector)
			let newWillBeginImplmentationBlock: @convention(block) (AnyObject, UIScrollView) -> Void =
			{ (self: AnyObject, scrollView: UIScrollView) in
				if superWillBeginMethod != nil {
					typealias Function = @convention(c) (AnyObject, Selector) -> Void
					unsafeBitCast(method_getImplementation(superWillBeginMethod!), to: Function.self)(self, willBeginDraggingSelector)
				}
				
				if objc_getAssociatedObject(self, (newSubclassName as NSString).utf8String!) != nil {
					willBeginClosure(scrollView)
				}
			}
			
			if class_addMethod(newSubclass, willBeginDraggingSelector, imp_implementationWithBlock(newWillBeginImplmentationBlock), willBeginDraggingMethodDescription.types) &&
					class_addMethod(newSubclass, didEndDraggingSelector, imp_implementationWithBlock(newDidEndImplmentationBlock), didEndDraggingMethodDescription.types) {
				objc_registerClassPair(newSubclass!)
			}
		}
		else {
			newSubclass = objc_lookUpClass((newSubclassName as NSString).utf8String!)
		}
		
		if newSubclass != nil {
			objc_setAssociatedObject(object, (newSubclassName as NSString).utf8String!, newSubclassName, .OBJC_ASSOCIATION_RETAIN)
			object_setClass(object, newSubclass!)
		}
	}
	
    public func makeUIView(context: UIViewRepresentableContext<PullToRefresh>) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }
    
    private func tableView(entry: UIView) -> UITableView? {
        
        // Search in ancestors
        if let tableView = Introspect.findAncestor(ofType: UITableView.self, from: entry) {
            return tableView
        }

        guard let viewHost = Introspect.findViewHost(from: entry) else {
            return nil
        }

        // Search in siblings
        return Introspect.previousSibling(containing: UITableView.self, from: viewHost)
    }

    public func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<PullToRefresh>) {
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            
            guard let tableView = self.tableView(entry: uiView) else {
                return
            }
            
            if let refreshControl = tableView.refreshControl {
                if self.isShowing {
                    refreshControl.beginRefreshing()
                } else {
                    refreshControl.endRefreshing()
                }
                return
            }
            
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.onValueChanged), for: .valueChanged)
            tableView.refreshControl = refreshControl
			
			registerScrollViewDelegates(
					onObject: ((tableView as UIScrollView).delegate!),
					willBeginDragging: { (scrollView: UIScrollView) in
						self.willBeginDragging()
					},
					didEndDragging: { (scrollView: UIScrollView, decelerate: Bool) in
						self.didEndDragging(decelerate)
					}
				)
		}
    }
    
    public func makeCoordinator() -> Coordinator {
        return Coordinator(onRefresh: onRefresh, isShowing: $isShowing)
    }
}

extension View {
    public func pullToRefresh(isShowing: Binding<Bool>,
							  willBeginDragging: @escaping () -> Void,
							  didEndDragging: @escaping (Bool) -> Void,
							  onRefresh: @escaping () -> Void) -> some View {
        return overlay(
			PullToRefresh(isShowing: isShowing, willBeginDragging: willBeginDragging, didEndDragging: didEndDragging, onRefresh: onRefresh)
                .frame(width: 0, height: 0)
        )
    }
}
