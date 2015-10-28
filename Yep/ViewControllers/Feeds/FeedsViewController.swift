//
//  FeedsViewController.swift
//  Yep
//
//  Created by nixzhu on 15/9/25.
//  Copyright © 2015年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift

class FeedsViewController: UIViewController {

    var skill: Skill?

    @IBOutlet weak var feedsTableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    var filterBarItem: UIBarButtonItem?
    
    lazy var filterView: DiscoverFilterView = DiscoverFilterView()
    
    lazy var skillTitleView: UIView = {

        let titleLabel = UILabel()

        let textAttributes = [
            NSForegroundColorAttributeName: UIColor.whiteColor(),
            NSFontAttributeName: UIFont.skillHomeTextLargeFont()
        ]

        let titleAttr = NSMutableAttributedString(string: self.skill?.localName ?? "", attributes:textAttributes)

        titleLabel.attributedText = titleAttr
        titleLabel.textAlignment = NSTextAlignment.Center
        titleLabel.backgroundColor = UIColor.yepTintColor()
        titleLabel.sizeToFit()

        titleLabel.bounds = CGRectInset(titleLabel.frame, -25.0, -4.0)

        titleLabel.layer.cornerRadius = titleLabel.frame.size.height/2.0
        titleLabel.layer.masksToBounds = true

        return titleLabel
        }()

    lazy var pullToRefreshView: PullToRefreshView = {

        let pullToRefreshView = PullToRefreshView()
        pullToRefreshView.delegate = self

        self.feedsTableView.insertSubview(pullToRefreshView, atIndex: 0)

        pullToRefreshView.translatesAutoresizingMaskIntoConstraints = false

        let viewsDictionary = [
            "pullToRefreshView": pullToRefreshView,
            "view": self.view,
        ]

        let constraintsV = NSLayoutConstraint.constraintsWithVisualFormat("V:|-(-200)-[pullToRefreshView(200)]", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: viewsDictionary)

        // 非常奇怪，若直接用 "H:|[pullToRefreshView]|" 得到的实际宽度为 0
        let constraintsH = NSLayoutConstraint.constraintsWithVisualFormat("H:|[pullToRefreshView(==view)]|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: viewsDictionary)

        NSLayoutConstraint.activateConstraints(constraintsV)
        NSLayoutConstraint.activateConstraints(constraintsH)
        
        return pullToRefreshView
        }()

    let feedSkillUsersCellID = "FeedSkillUsersCell"
    let feedCellID = "FeedCell"

    lazy var noFeedsFooterView: InfoView = InfoView(NSLocalizedString("No Feeds.", comment: ""))

    var feeds = [DiscoveredFeed]()

    private func updateFeedsTableViewOrInsertWithIndexPaths(indexPaths: [NSIndexPath]?) {

        dispatch_async(dispatch_get_main_queue()) { [weak self] in

            if let indexPaths = indexPaths {

                // refresh skillUsers

                let skillUsersIndexPath = NSIndexPath(forRow: 0, inSection: Section.SkillUsers.rawValue)
                if let cell = self?.feedsTableView.cellForRowAtIndexPath(skillUsersIndexPath) as? FeedSkillUsersCell, feeds = self?.feeds {
                    cell.configureWithFeeds(feeds)
                }

                // insert

                self?.feedsTableView.insertRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic)

            } else {

                // or reload

                self?.feedsTableView.reloadData()
            }

            if let strongSelf = self {
                strongSelf.feedsTableView.tableFooterView = strongSelf.feeds.isEmpty ? strongSelf.noFeedsFooterView : UIView()
            }
        }
    }

    private var feedHeightHash = [String: CGFloat]()

    private func heightOfFeed(feed: DiscoveredFeed) -> CGFloat {

        let key = feed.id

        if let height = feedHeightHash[key] {
            return height
        } else {
            let height = FeedCell.heightOfFeed(feed)

            if !key.isEmpty {
                feedHeightHash[key] = height
            }

            return height
        }
    }
    
    var feedSortStyle: FeedSortStyle = .Default {
        didSet {
            
            feeds = [DiscoveredFeed]()
            
            feedsTableView.reloadData()
            
            activityIndicator.startAnimating()
            
            updateFeeds()
        }
    }

    

    var navigationControllerDelegate: ConversationMessagePreviewNavigationControllerDelegate?
    var originalNavigationControllerDelegate: UINavigationControllerDelegate?
    
    deinit {
        print("Deinit FeedsViewControler")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        
        // 优先处理侧滑，而不是 scrollView 的上下滚动，避免出现你想侧滑返回的时候，结果触发了 scrollView 的上下滚动
        if let gestures = navigationController?.view.gestureRecognizers {
            for recognizer in gestures {
                if recognizer.isKindOfClass(UIScreenEdgePanGestureRecognizer) {
                    feedsTableView.panGestureRecognizer.requireGestureRecognizerToFail(recognizer as! UIScreenEdgePanGestureRecognizer)
                    println("Require UIScreenEdgePanGestureRecognizer to failed")
                    break
                }
            }
        }

        title = NSLocalizedString("Feeds", comment: "")

        if skill != nil {
            navigationItem.titleView = skillTitleView
        } else {
            filterBarItem = UIBarButtonItem(title: "", style: UIBarButtonItemStyle.Plain, target: self, action: "showFilter:")
            navigationItem.leftBarButtonItem = filterBarItem
        }

        feedsTableView.backgroundColor = UIColor.whiteColor()
        feedsTableView.tableFooterView = UIView()
        feedsTableView.separatorColor = UIColor.yepCellSeparatorColor()

        feedsTableView.registerNib(UINib(nibName: feedSkillUsersCellID, bundle: nil), forCellReuseIdentifier: feedSkillUsersCellID)
        feedsTableView.registerNib(UINib(nibName: feedCellID, bundle: nil), forCellReuseIdentifier: feedCellID)

        feedSortStyle = .Time
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        // 尝试恢复原始的 NavigationControllerDelegate，如果自定义 push 了才需要
        if let delegate = originalNavigationControllerDelegate {
            navigationController?.delegate = delegate
        }

        navigationController?.setNavigationBarHidden(false, animated: false)

        tabBarController?.tabBar.hidden = (skill == nil) ? false : true
    }

    // MARK: - Actions

    @IBAction func showFilter(sender: AnyObject) {
        
        if feedSortStyle != .Time {
            filterView.currentDiscoveredUserSortStyle = DiscoveredUserSortStyle(rawValue: feedSortStyle.rawValue)!
        } else {
            filterView.currentDiscoveredUserSortStyle = .LastSignIn
        }
        
        filterView.filterAction = { [weak self] discoveredUserSortStyle in
            
            if discoveredUserSortStyle != .LastSignIn {
                self?.feedSortStyle = FeedSortStyle(rawValue: discoveredUserSortStyle.rawValue)!
            } else {
                self?.feedSortStyle = .Time
            }
        }
        
        if let window = view.window {
            filterView.showInView(window)
        }
    }
    
    func updateFeeds(finish: (() -> Void)? = nil) {
        
        if let filterBarItem = filterBarItem {
            filterBarItem.title = feedSortStyle.nameWithArrow
        }

        activityIndicator.startAnimating()

        discoverFeedsWithSortStyle(feedSortStyle, skill: skill, pageIndex: 1, perPage: 50, failureHandler: { reason, errorMessage in

            dispatch_async(dispatch_get_main_queue()) { [weak self] in
                self?.activityIndicator.stopAnimating()

                finish?()
            }

            defaultFailureHandler(reason, errorMessage: errorMessage)

        }, completion: { [weak self] feeds in

            dispatch_async(dispatch_get_main_queue()) { [weak self] in
                self?.activityIndicator.stopAnimating()

                finish?()
            }

            if let strongSelf = self {

//                let oldFeedSet = Set(strongSelf.feeds)
//                let newFeedSet = Set(feeds)

//                let unionFeedSet = oldFeedSet.union(newFeedSet)
//                let allNewFeedSet = newFeedSet.subtract(oldFeedSet)

//                let allFeeds = Array(unionFeedSet)
//
//                let newIndexPaths = allNewFeedSet.map({ allFeeds.indexOf($0) }).flatMap({ $0 }).map({ NSIndexPath(forRow: $0, inSection: Section.Feed.rawValue) })

                dispatch_async(dispatch_get_main_queue()) {

                    strongSelf.feeds = feeds
                    strongSelf.feedsTableView.reloadData() // 服务端有新的排序算法，以及避免刷新后消息数字更新不及时的问题
                    
//                    if newIndexPaths.count == allNewFeedSet.count {
//                        strongSelf.updateFeedsTableViewOrInsertWithIndexPaths(newIndexPaths)
//
//                    } else {
//                        strongSelf.updateFeedsTableViewOrInsertWithIndexPaths(nil)
//                    }
                }
            }
        })
    }

    @IBAction func showNewFeed(sender: AnyObject) {

        let vc = self.storyboard?.instantiateViewControllerWithIdentifier("NewFeedViewController") as! NewFeedViewController

        vc.preparedSkill = skill

        vc.afterCreatedFeedAction = { [weak self] feed in

            dispatch_async(dispatch_get_main_queue()) {

                if let strongSelf = self {

                    strongSelf.feeds.insert(feed, atIndex: 0)

                    let indexPath = NSIndexPath(forRow: 0, inSection: Section.Feed.rawValue)
                    strongSelf.updateFeedsTableViewOrInsertWithIndexPaths([indexPath])
                }
            }
            
            joinGroup(groupID: feed.groupID, failureHandler: nil, completion: {
                
            })
        }

        let navi = UINavigationController(rootViewController: vc)

        self.presentViewController(navi, animated: true, completion: nil)
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {

        guard let identifier = segue.identifier else {
            return
        }

        switch identifier {

        case "showProfile":

            let vc = segue.destinationViewController as! ProfileViewController

            if let indexPath = sender as? NSIndexPath {
                let discoveredUser = feeds[indexPath.row].creator
                vc.profileUser = ProfileUser.DiscoveredUserType(discoveredUser)
            }

            vc.fromType = .None
            vc.setBackButtonWithTitle()

            vc.hidesBottomBarWhenPushed = true

        case "showSkillHome":

            let vc = segue.destinationViewController as! SkillHomeViewController

            if let skill = skill {
                vc.skill = SkillCell.Skill(ID: skill.id, localName: skill.localName, coverURLString: skill.coverURLString, category: nil)
            }

            vc.hidesBottomBarWhenPushed = true

        case "showFeedsWithSkill":

            let vc = segue.destinationViewController as! FeedsViewController

            if let indexPath = sender as? NSIndexPath {
                vc.skill = feeds[indexPath.row].skill
            }

            vc.hidesBottomBarWhenPushed = true

        case "showConversation":

            guard let
                indexPath = sender as? NSIndexPath,
                feedData = feeds[safe: indexPath.row],
                realm = try? Realm() else {
                    return
            }
            
            let vc = segue.destinationViewController as! ConversationViewController
            
            let groupID = feedData.groupID
            var group = groupWithGroupID(groupID, inRealm: realm)

            if group == nil {

                let newGroup = Group()
                newGroup.groupID = groupID

                let _ = try? realm.write {
                    realm.add(newGroup)
                }

                group = newGroup
            }

            guard let feedGroup = group else {
                return
            }

            if feedGroup.conversation == nil {

                let newConversation = Conversation()

                newConversation.type = ConversationType.Group.rawValue
                newConversation.withGroup = feedGroup

                let _ = try? realm.write {
                    realm.add(newConversation)
                }
            }

            guard let feedConversation = feedGroup.conversation else {
                return
            }

            vc.conversation = feedConversation
            
            if let group = group {
                saveFeedWithFeedDataWithoutFullGroup(feedData, group: group, inRealm: realm)
            }

            vc.conversationFeed = ConversationFeed.DiscoveredFeedType(feedData)

        case "showFeedMedia":

            let info = sender as! [String: AnyObject]

            let vc = segue.destinationViewController as! MessageMediaViewController
            vc.previewMedia = PreviewMedia.AttachmentType(imageURL: info["imageURL"] as! NSURL )

            let transitionView = info["transitionView"] as! UIImageView

            let delegate = ConversationMessagePreviewNavigationControllerDelegate()
            delegate.isFeedMedia = true
            delegate.snapshot = UIScreen.mainScreen().snapshotViewAfterScreenUpdates(false)

            var frame = transitionView.convertRect(transitionView.frame, toView: view)
            delegate.frame = frame
            if let image = transitionView.image {
                let width = image.size.width
                let height = image.size.height
                if width > height {
                    let newWidth = frame.width * (width / height)
                    frame.origin.x -= (newWidth - frame.width) / 2
                    frame.size.width = newWidth
                } else {
                    let newHeight = frame.height * (height / width)
                    frame.origin.y -= (newHeight - frame.height) / 2
                    frame.size.height = newHeight
                }
                delegate.thumbnailImage = image
            }
            delegate.thumbnailFrame = frame

            delegate.transitionView = transitionView

            navigationControllerDelegate = delegate

            // 在自定义 push 之前，记录原始的 NavigationControllerDelegate 以便 pop 后恢复
            originalNavigationControllerDelegate = navigationController!.delegate

            navigationController?.delegate = delegate
            
            break

        default:
            break
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension FeedsViewController: UITableViewDataSource, UITableViewDelegate {

    enum Section: Int {
        case SkillUsers
        case Feed
    }

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {

        return 2
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

        switch section {
        case Section.SkillUsers.rawValue:
            return (skill == nil) ? 0 : 1
        case Section.Feed.rawValue:
            return feeds.count
        default:
            return 0
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        switch indexPath.section {

        case Section.SkillUsers.rawValue:

            let cell = tableView.dequeueReusableCellWithIdentifier(feedSkillUsersCellID) as! FeedSkillUsersCell

            cell.configureWithFeeds(feeds)

            return cell

        case Section.Feed.rawValue:

            let cell = tableView.dequeueReusableCellWithIdentifier(feedCellID) as! FeedCell

            let feed = feeds[indexPath.item]

            cell.configureWithFeed(feed, needShowSkill: (skill == nil) ? true : false)

            cell.tapAvatarAction = { [weak self] cell in
                if let indexPath = tableView.indexPathForCell(cell) { // 不直接捕捉 indexPath
                    self?.performSegueWithIdentifier("showProfile", sender: indexPath)
                }
            }

            cell.tapSkillAction = { [weak self] cell in
                if let indexPath = tableView.indexPathForCell(cell) { // 不直接捕捉 indexPath
                    self?.performSegueWithIdentifier("showFeedsWithSkill", sender: indexPath)
                }
            }

            cell.tapMediaAction = { [weak self] transitionView, imageURL in
                let info = [
                    "transitionView": transitionView,
                    "imageURL": imageURL,
                ]
                self?.performSegueWithIdentifier("showFeedMedia", sender: info)
            }

            // simulate select effects when tap on messageTextView or cell.mediaCollectionView's space part
            // 不能直接捕捉 indexPath，不然新插入后，之前捕捉的 indexPath 不能代表 cell 的新位置，模拟点击会错位到其它 cell
            cell.touchesBeganAction = { [weak self] cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                self?.tableView(tableView, willSelectRowAtIndexPath: indexPath)
                tableView.selectRowAtIndexPath(indexPath, animated: false, scrollPosition: .None)
            }
            cell.touchesEndedAction = { [weak self] cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                delay(0.03) { [weak self] in
                    self?.tableView(tableView, didSelectRowAtIndexPath: indexPath)
                }
            }
            cell.touchesCancelledAction = { cell in
                guard let indexPath = tableView.indexPathForCell(cell) else {
                    return
                }
                tableView.deselectRowAtIndexPath(indexPath, animated: true)
            }
            
            return cell

        default:
            return UITableViewCell()
        }
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {

        switch indexPath.section {

        case Section.SkillUsers.rawValue:
            return 70

        case Section.Feed.rawValue:
            let feed = feeds[indexPath.item]
            return heightOfFeed(feed)

        default:
            return 0
        }
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        return indexPath
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        switch indexPath.section {

        case Section.SkillUsers.rawValue:
            performSegueWithIdentifier("showSkillHome", sender: nil)

        case Section.Feed.rawValue:
            performSegueWithIdentifier("showConversation", sender: indexPath)

        default:
            break
        }
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(scrollView: UIScrollView) {

        pullToRefreshView.scrollViewDidScroll(scrollView)
    }

    func scrollViewWillEndDragging(scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {

        pullToRefreshView.scrollViewWillEndDragging(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }
}

// MARK: PullToRefreshViewDelegate

extension FeedsViewController: PullToRefreshViewDelegate {

    func pulllToRefreshViewDidRefresh(pulllToRefreshView: PullToRefreshView) {

        activityIndicator.alpha = 0

        updateFeeds { [weak self] in
            pulllToRefreshView.endRefreshingAndDoFurtherAction() {}

            self?.activityIndicator.alpha = 1
        }
    }
    
    func scrollView() -> UIScrollView {
        return feedsTableView
    }
}

