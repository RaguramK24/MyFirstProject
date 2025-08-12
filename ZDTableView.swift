//
//  ZDTableView.swift
//  Dashboards
//
//  Created by Raguram K on 26/03/25.
//  Copyright © 2025 Raguram K. All rights reserved.
//

import UIKit
import zdcore

struct UniqueItem: Hashable {
    let section: Int
    let item: Int
}

class ZDTableView: UIView, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout  {
    
    weak var reportModal : ReportModal? = nil
    
    var tableState : ZDTableState? = nil
    weak var delegateTopresenter:TableViewToPresenter? = nil
    weak var delegateToVudView: TableViewToVUDView? = nil
    weak var dashboardTableViewToPresanter : DashboardTableViewToPresanter? = nil
    var collectionView: UICollectionView!
    var headerCollectionView: UICollectionView!
    var headerCollectionViewHeightAnchor : NSLayoutConstraint!
    private let verticalScrollOptionsContainer = TableChartScrollButtonView(isVertical: true)
    private let horizontalScrollOptionsContainer = TableChartScrollButtonView(isVertical: false)
    var isfullview:Bool = true
    var isRequestinProgress = false
    
    var verticalresize = false
    
    private var hideTimer: Timer?
    private var previousContentOffset: CGPoint = .zero
    private var previousContentSizeHeight: CGFloat = .zero
    private var isVerticalDownScroll: Bool? = nil
    private var isScrolling: Bool = false
    
    let VISIBLE_WINDOW = 200
    var dataSource: UICollectionViewDiffableDataSource<Int, UniqueItem>!
    var snapshot = NSDiffableDataSourceSnapshot<Int, UniqueItem>()
    
    var currentSectionWindow = 0..<0
    var scrollCheckTimer: Timer?
    
    var dataFetchMap : [Int : Bool?] = [:]
    var scrollDirection : ScrollType? = nil
//MARK: SetUp
    
    convenience init(tableState: ZDTableState?) {
        self.init(frame: .zero)
        self.tableState = tableState
        initializeData()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCollectionView()
        setUpScrollOptionView()
    }
    
    func setupCollectionView() {
        let headerlayout = UICollectionViewFlowLayout()
        headerlayout.scrollDirection = .horizontal
        headerlayout.minimumLineSpacing = 0
        headerlayout.minimumInteritemSpacing = 0
        
        // Initialize CollectionView
        headerCollectionView = UICollectionView(frame: self.bounds, collectionViewLayout: headerlayout)
        headerCollectionView.dataSource = self
        headerCollectionView.delegate = self
        headerCollectionView.bounces = false
        headerCollectionView.alwaysBounceVertical = false
        headerCollectionView.backgroundColor = nil
        headerCollectionView.showsHorizontalScrollIndicator = false
        
        headerCollectionView.register(ZDTableHeaderCell.self, forCellWithReuseIdentifier: "ZDTableHeaderCell")
        self.addSubview(headerCollectionView)
        headerCollectionView.translatesAutoresizingMaskIntoConstraints = false
        headerCollectionView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        headerCollectionView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        headerCollectionView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        headerCollectionViewHeightAnchor = headerCollectionView.heightAnchor.constraint(equalToConstant: 40)
        headerCollectionViewHeightAnchor.isActive = true
        
        let layout = createLayout()
        
        // Initialize CollectionView
        collectionView = UICollectionView(frame: self.bounds, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.backgroundColor = nil
        collectionView.bounces = false
        
        collectionView?.register(ZDTableCollectionViewCell.self, forCellWithReuseIdentifier: "ZDTableCollectionViewCell")
        collectionView?.register(ZDTableTextWithIconLeftCell.self, forCellWithReuseIdentifier: "ZDTableTextWithIconLeftCell")
        collectionView?.register(ZDTableTextWithRightIconCell.self, forCellWithReuseIdentifier: "ZDTableTextWithRightIconCell")
        
        self.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        collectionView.topAnchor.constraint(equalTo: headerCollectionView.bottomAnchor).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        
        
        dataSource = UICollectionViewDiffableDataSource<Int, UniqueItem>(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            if let state = self.tableState, let rows = state.rowData[KotlinInt(integerLiteral: indexPath.section + 1)], let row = rows[safe: indexPath.item]
            {
                if let singleLabelCell = collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableCollectionViewCell", for: indexPath) as? ZDTableCollectionViewCell
                {
                    singleLabelCell.accessibilityIdentifier = "Row : \(indexPath.section)  Column : \(indexPath.item)"
                    singleLabelCell.row = row
                    singleLabelCell.tableState = self.tableState
                    singleLabelCell.collectionView.reloadData()
                    return singleLabelCell
                }
            }
            return collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableCollectionViewCell", for: indexPath)
        }
    }
    
    func setUpScrollOptionView()
    {
        self.addSubViews(self.verticalScrollOptionsContainer, self.horizontalScrollOptionsContainer)
        
        NSLayoutConstraint.activate([
            verticalScrollOptionsContainer.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            verticalScrollOptionsContainer.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor, constant: -11),
            verticalScrollOptionsContainer.heightAnchor.constraint(equalToConstant: 75),
            verticalScrollOptionsContainer.widthAnchor.constraint(equalToConstant: 28),
            
            horizontalScrollOptionsContainer.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -11),
            horizontalScrollOptionsContainer.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            horizontalScrollOptionsContainer.heightAnchor.constraint(equalToConstant: 28),
            horizontalScrollOptionsContainer.widthAnchor.constraint(equalToConstant: 75),
        ])
        
        verticalScrollOptionsContainer.isHidden = true
        horizontalScrollOptionsContainer.isHidden = true
        
        verticalScrollOptionsContainer.delegate = self
        horizontalScrollOptionsContainer.delegate = self
    }
    
    func deInitialize()
    {
        tableState = nil
        reportModal = nil
        delegateTopresenter = nil
        delegateToVudView = nil
        dashboardTableViewToPresanter = nil
        
        isfullview = false
        isRequestinProgress = false
        verticalresize = false
        previousContentOffset = .zero
        previousContentSizeHeight = .zero
        isVerticalDownScroll = nil
        isScrolling = false
        currentSectionWindow = 0..<0
        dataFetchMap = [:]
        snapshot.deleteAllItems()
        headerCollectionViewHeightAnchor.constant = 40
        headerCollectionView.reloadData()
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        // Cancel the task when the view controller is deallocated
        deInitialize()
    }
    
    
    func applySnapshotForWindow(_ window: Range<Int>) {
        guard window != currentSectionWindow else { return }
        
        currentSectionWindow = window
        let prevPackLast = (window.first ?? 1) - 2
        if snapshot.sectionIdentifiers.contains(prevPackLast)
        {
            snapshot.insertSections(Array(window), afterSection: prevPackLast)
        }
        else
        {
            snapshot.appendSections(Array(window))
        }
        for section in window {
            var itemCount = 0
            for row in self.tableState?.rowData[KotlinInt(integerLiteral: section + 1)] ?? [] {
                itemCount += row.cells.count
            }
            let items = [UniqueItem(section: section, item: 0)]
            snapshot.appendItems(items, toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        headerCollectionViewHeightAnchor.constant = 40
        headerCollectionView.reloadData()
    }
    
//MARK: Layout
    /// Creates a compositional layout with a sticky header
    func createLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            var items: [NSCollectionLayoutItem] = []
            var groupWidth = CGFloat(0)
            let sections = self.tableState?.rowData[KotlinInt(integerLiteral: sectionIndex+1)] ?? []
            for section in sections
            {
                groupWidth = 0
                for index in 0..<section.cells.count
                {
                    let width = CGFloat(truncating: self.tableState?.columnWidths[index] ?? 150)
                    groupWidth += width
                }
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(groupWidth), heightDimension: .absolute(40))
                items.append(NSCollectionLayoutItem(layoutSize: itemSize))
            }
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(groupWidth),
                heightDimension: .absolute(CGFloat(sections.count * 40))
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: items)
            
            // Define a section (Each section = 1 Row)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 1
            return section
        }
    }
    
    
    func getCellForIndexPath(indexPath: IndexPath, collectionView: UICollectionView) -> UICollectionViewCell? {
         if let state = tableState, let rows = state.rowData[KotlinInt(integerLiteral: indexPath.section + 1)]
        {
            if rows.count == 1, let row = rows.first, let cellObject = row.cells[safe: indexPath.item]
            {
                if let singleLabelCell = collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableSingleTextCell", for: indexPath) as? ZDTableSingleTextCell
                {
                    singleLabelCell.accessibilityIdentifier = "Row : \(indexPath.section)  Column : \(indexPath.item)"
                    singleLabelCell.updateContent(cellObject: cellObject, state: state, row: row, index: indexPath.item, isHeaderCell: false)
                    return singleLabelCell
                }
            }
            else
            {
                var item = indexPath.item
                var row: ZDTableState.Row? = nil
                for row_ in rows
                {
                    if item < (row_.cells.count + 1)
                    {
                        row = row_
                        break
                    }
                    else
                    {
                        item -= (row_.cells.count + 1)
                    }
                }
                if let row, let cellObject = row.cells[safe: item]
                {
                    if let singleLabelCell = collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableSingleTextCell", for: indexPath) as? ZDTableSingleTextCell
                    {
                        singleLabelCell.accessibilityIdentifier = "Row : \(indexPath.section)  Column : \(indexPath.item)"
                        singleLabelCell.updateContent(cellObject: cellObject, state: state, row: row, index: item, isHeaderCell: false)
                        return singleLabelCell
                    }
                }
            }
        }
        return nil
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let isVerticalDownScroll
        {
            let packIndex =  getDataPackIndex(section: isVerticalDownScroll ? indexPath.section + 70 : indexPath.section - 70)
            if dataFetchMap[packIndex] == nil {
                fetchNextTableData(dataPackIndex: packIndex){startIndex, modal in
                    DispatchQueue.main.async {
                        if let modal{
                            self.applySnapshotForWindow(startIndex..<(startIndex+Int(modal.navConfig.batchCount)))
                        }
                    }
                }
            }
        }
    }
    
    func getDataPackIndex(section: Int) -> Int {
        return abs(section/200)
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tableState?.headers.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: CGFloat(truncating: tableState?.columnWidths[safe: indexPath.item] ?? 0), height: 40)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableHeaderCell", for: indexPath) as? ZDTableHeaderCell
        {
            if let tableState,let header = tableState.headers[safe: indexPath.item]
            {
                cell.updateContent(cellObject: header, state: tableState, row: nil, index: indexPath.item, isHeaderCell: true)
                cell.updateDatatypeIcon(cellObject: header)
            }
            return cell
        }
        else
        {
            return collectionView.dequeueReusableCell(withReuseIdentifier: "ZDTableSingleTextCell", for: indexPath)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
    
    
    func fetchNextTableData(dataPackIndex: Int, returnBlock:  @escaping (_ startIndex: Int, _ tableModal : ZDTableModal?) -> Void)
    {
        if dataFetchMap[dataPackIndex] == false {
            return
        }
        dataFetchMap[dataPackIndex] = false
        let limit = (dataPackIndex*200)+1
        if let delegateTopresenter
        {
            delegateTopresenter.getTablePage(limit: limit, returnBlock: { report in
                let modal = self.loadReportResponse(reportData: report?.reportData)
                self.dataFetchMap[dataPackIndex] = modal != nil ? true : nil
                returnBlock(limit-1, modal)
            })
        }
        else if let delegateToVudView {
            delegateToVudView.getTablePage(limit: limit, returnBlock: { (reportData) in
                let modal = self.loadReportResponse(reportData: reportData)
                self.dataFetchMap[dataPackIndex] = modal != nil ? true : nil
                returnBlock(limit-1, modal)
            })
        }
        else if let reportModal {
            dashboardTableViewToPresanter?.getTablePage(limit: 0, Report_Properties: reportModal) { report in
                let modal = self.loadReportResponse(reportData: report?.reportData)
                self.dataFetchMap[dataPackIndex] = modal != nil ? true : nil
                returnBlock(limit-1, modal)
            }
        }
    }
    
    func loadReportResponse(reportData : ReportDataModal?) -> ZDTableModal?
    {
        if let reportDataString = reportData?.reportDataString, let modal = ZDCommonTable.companion.initializeTable(responseString: reportDataString) {
            self.tableState?.addNextBatchData(newTableData: modal)
            
            return modal
        }
        else
        {
            return nil
        }
    }
}

extension ZDTableView: UIScrollViewDelegate
{
    
    func updateTheme(cardThemeModal:ZDReportViewTheme) {
        backgroundColor = cardThemeModal.viewBackgroundColor.getColor()
        collectionView?.backgroundColor = cardThemeModal.viewBackgroundColor.getColor()
    }
    
    
    func initializeData()
    {
        applySnapshotForWindow(0..<(tableState?.rowData.count ?? 0))
        let numberOfDataSection : Int = Int((tableState?.currentNavConfig.totalRecord ?? 0)/200)
        for i in 0...numberOfDataSection
        {
            if tableState?.rowData[KotlinInt(integerLiteral: (i*200) + 1)] != nil
            {
                dataFetchMap[i] = true
            }
            else
            {
                dataFetchMap[i] = nil
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hideScrollButtonView()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isScrolling { return }
        isScrolling = true
        
        let offsetX = scrollView.contentOffset.x  // Only take horizontal scrolling
        if scrollView == headerCollectionView {
            collectionView.delegate = nil
            collectionView.contentOffset.x = offsetX
            collectionView.delegate = self
        } else if scrollView == collectionView {
            headerCollectionView.delegate = nil
            headerCollectionView.contentOffset.x = offsetX
            headerCollectionView.delegate = self
        }
        
        if isfullview {
            if scrollDirection == nil
            {
                scrollDirection = getScrollDirection(currentContentOffset: scrollView.contentOffset)
            }
            if let scrollDirection
            {
                if scrollDirection == .vertical {
                    verticalScrollOptionsContainer.updateButtons(contentOffset: scrollView.contentOffset, isVerticalEnd: isVerticalEnd(scrollView: scrollView), isHorizontalEnd: isHorizontalEnd(scrollView: scrollView))
                    showScrollButtonView(isVerticalScroll: true)
                } else {
                    horizontalScrollOptionsContainer.updateButtons(contentOffset: scrollView.contentOffset, isVerticalEnd: isVerticalEnd(scrollView: scrollView), isHorizontalEnd: isHorizontalEnd(scrollView: scrollView))
                    showScrollButtonView(isVerticalScroll: false)
                }
            }
        }
        previousContentOffset = scrollView.contentOffset
        isScrolling = false
    }
    
    private func isVerticalEnd(scrollView: UIScrollView) -> Bool {
        let contentHeight = scrollView.contentSize.height
        let contentOffsetY = scrollView.contentOffset.y
        let scrollViewHeight = scrollView.frame.size.height
        
        if (contentOffsetY + scrollViewHeight) >= contentHeight {
            return true
        } else {
            return false
        }
    }
    
    private func isHorizontalEnd(scrollView: UIScrollView) -> Bool {
        let contentWidth = scrollView.contentSize.width
        let contentOffsetX = scrollView.contentOffset.x
        let scrollViewWidth = scrollView.frame.size.width
        
        if (contentOffsetX + scrollViewWidth) >= contentWidth {
            return true
        } else {
            return false
        }
    }
    
    private func getScrollDirection(currentContentOffset: CGPoint) -> ScrollType {
        var scrollType: ScrollType = .vertical
        isVerticalDownScroll = nil
        let yDiff = abs(currentContentOffset.y - previousContentOffset.y)
        let xDiff = abs(currentContentOffset.x - previousContentOffset.x)
        if yDiff > xDiff {
            scrollType = .vertical
        }
        else
        {
            scrollType = .horizontal
        }
        isVerticalDownScroll = yDiff > 0
        return scrollType
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isScrolling = false
        if !isfullview { return }
        if !decelerate {
            startHideTimer()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isScrolling = false
        if !isfullview { return }
        startHideTimer()
    }
    
    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(hideScrollButtonView), userInfo: nil, repeats: false)
    }
    
    @objc private func hideScrollButtonView() {
        scrollDirection = nil
        UIView.animate(withDuration: 0.1) {
            self.verticalScrollOptionsContainer.isHidden = true
            self.horizontalScrollOptionsContainer.isHidden = true
        }
    }
    
    private func showScrollButtonView(isVerticalScroll: Bool) {
        UIView.animate(withDuration: 0.1) {
            if isVerticalScroll {
                self.horizontalScrollOptionsContainer.isHidden = true
                self.verticalScrollOptionsContainer.isHidden = false
            } else {
                self.verticalScrollOptionsContainer.isHidden = true
                self.horizontalScrollOptionsContainer.isHidden = false
            }
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isScrolling = false
        if !isfullview { return }
        startHideTimer()
    }
    
    
}

extension ZDTableView : TableChartScrollButtonViewToTableView {
    
    func scrollViewTo(direction: GradientDirection) {
        DispatchQueue.main.async {
            switch direction {
            case .leftToRight:
                self.scrollToRight()
            case .rightToLeft:
                self.scrollToLeft()
            case .topToBottom:
                self.scrollToBottom()
            case .bottomToTop:
                self.scrollToTop()
            }
        }
    }
    
    private func scrollToRight() {
        let currentOFFset = collectionView.contentOffset
        collectionView.setContentOffset(CGPoint(x: collectionView.contentSize.width - collectionView.bounds.width, y: currentOFFset.y), animated: true)
    }
    
    private func scrollToLeft() {
        let currentOFFset = collectionView.contentOffset
        collectionView.setContentOffset(CGPoint(x: 0, y: currentOFFset.y), animated: true)
    }
    
    private func scrollToBottom(isSecondRequest: Bool = false) {
        DispatchQueue.main.async {
            self.moveToBottom()
        }
    }
     private func moveToBottom() {
        DispatchQueue.main.async {
            self.isScrolling = true
            let lastSection = Int(self.tableState?.currentNavConfig.totalRecord ?? 0)
            let packIndex =  self.getDataPackIndex(section: lastSection)
            if self.dataFetchMap[packIndex] == nil {
                self.fetchNextTableData(dataPackIndex: packIndex){startIndex, modal in
                    DispatchQueue.main.async {
                        if let modal{
                            self.applySnapshotForWindow(startIndex..<(startIndex+Int(modal.navConfig.batchCount)))
                            self.collectionView.scrollToLast()
                        }
                    }
                }
            }
            else
            {
                self.collectionView.scrollToLast()
            }
        }
    }
    
    private func scrollToTop() {
        DispatchQueue.main.async {
            let currentOFFset = self.collectionView.contentOffset
            self.collectionView.setContentOffset(CGPoint(x: currentOFFset.x, y: 0), animated: true)
        }
    }
}


final class ZDTableTwoWayPanCollectionView: UICollectionView, UIGestureRecognizerDelegate {

    private var customPan: UIPanGestureRecognizer!
    private var isManualPanScroll = false

    func enableTwoWayPan() {
        // Disable native scroll so our gesture fully controls both axes
        isScrollEnabled = false

        // Add custom pan
        customPan = UIPanGestureRecognizer(target: self, action: #selector(handleCustomPan(_:)))
        customPan.delegate = self
        addGestureRecognizer(customPan)
    }

    @objc private func handleCustomPan(_ gesture: UIPanGestureRecognizer) {
        isManualPanScroll = true
        defer { isManualPanScroll = false }

        let translation = gesture.translation(in: self)
        var offset = contentOffset

        offset.x -= translation.x
        offset.y -= translation.y

        // Clamp to avoid bounce
        offset.x = max(0, min(offset.x, contentSize.width - bounds.width))
        offset.y = max(0, min(offset.y, contentSize.height - bounds.height))

        setContentOffset(offset, animated: false)
        gesture.setTranslation(.zero, in: self)
    }

    // Take over only when UIKit wouldn't scroll
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == customPan else { return true }

        // If both directions have scrollable content, always allow
        let canScrollHorizontally = contentSize.width > bounds.width
        let canScrollVertically = contentSize.height > bounds.height

        return canScrollHorizontally || canScrollVertically
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous so UIKit's vertical scroll can still work if you enable isScrollEnabled
        return true
    }
}
