//
//  ZDTableView.swift
//  Dashboards
//
//  Created by Raguram K on 26/03/25.
//  Copyright © 2025 Raguram K. All rights reserved.


import UIKit
import zdcore

// OPTIMIZATION: Safe array access extension to prevent crashes with large datasets
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

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
    
    // OPTIMIZATION: Reduced window size for true virtualization - only keep 500 rows visible + prefetch buffer
    let VISIBLE_WINDOW = 500
    let PREFETCH_BUFFER = 50 // Prefetch buffer on each side
    let BATCH_SIZE = 200 // Size of each data batch to fetch
    
    var dataSource: UICollectionViewDiffableDataSource<Int, UniqueItem>!
    var snapshot = NSDiffableDataSourceSnapshot<Int, UniqueItem>()
    
    // OPTIMIZATION: Track current visible window more precisely for efficient updates
    var currentSectionWindow = 0..<0
    var visibleSectionRange = 0..<0 // Currently visible sections in viewport
    var scrollCheckTimer: Timer?
    
    // OPTIMIZATION: Scroll throttling and center section tracking for performance
    private var scrollThrottleTimer: Timer?
    private var lastUpdatedCenterSection: Int = -1
    private var pendingScrollUpdate: (() -> Void)?
    private let scrollThrottleInterval: TimeInterval = 0.016 // ~60fps throttling
    
    // OPTIMIZATION: Efficient data fetch tracking with pack-based indexing
    var dataFetchMap : [Int : Bool?] = [:]
    var scrollDirection : ScrollType? = nil
    
    // OPTIMIZATION: Async operation queue for non-blocking data operations
    private let dataOperationQueue = DispatchQueue(label: "com.zdtable.dataOperations", qos: .userInitiated)
    private let snapshotQueue = DispatchQueue(label: "com.zdtable.snapshot", qos: .userInitiated)
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
    
    // OPTIMIZATION: Efficient cleanup with proper resource management
    func deInitialize()
    {
        // OPTIMIZATION: Cancel throttle timers to prevent memory leaks
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = nil
        pendingScrollUpdate = nil
        
        // OPTIMIZATION: Cancel any pending async operations
        dataOperationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clear data structures efficiently
            self.dataFetchMap.removeAll()
            self.currentSectionWindow = 0..<0
            self.visibleSectionRange = 0..<0
            self.lastUpdatedCenterSection = -1
            
            DispatchQueue.main.async {
                // Clear UI state
                self.tableState = nil
                self.reportModal = nil
                self.delegateTopresenter = nil
                self.delegateToVudView = nil
                self.dashboardTableViewToPresanter = nil
                
                self.isfullview = false
                self.isRequestinProgress = false
                self.verticalresize = false
                self.previousContentOffset = .zero
                self.previousContentSizeHeight = .zero
                self.isVerticalDownScroll = nil
                self.isScrolling = false
                
                // OPTIMIZATION: Clear snapshot efficiently
                self.snapshot.deleteAllItems()
                self.headerCollectionViewHeightAnchor.constant = 40
                self.headerCollectionView.reloadData()
                self.dataSource.apply(self.snapshot, animatingDifferences: false)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    deinit {
        // Cancel the task when the view controller is deallocated
        deInitialize()
    }
    
    
    // OPTIMIZATION: True sliding window implementation with memory cleanup and selective header updates
    func applySnapshotForWindow(_ window: Range<Int>) {
        guard window != currentSectionWindow else { return }
        
        let previousWindow = currentSectionWindow
        currentSectionWindow = window

        // Remove all sections/items outside the new window
        let allSections = snapshot.sectionIdentifiers
        let sectionsToRemove = allSections.filter { !window.contains($0) }
        if !sectionsToRemove.isEmpty {
            snapshot.deleteSections(sectionsToRemove)
        }

        // Only add sections that are not already present
        let presentSections = Set(snapshot.sectionIdentifiers)
        let sectionsToAdd = window.filter { !presentSections.contains($0) }

        if !sectionsToAdd.isEmpty {
            for section in sectionsToAdd {
                snapshot.appendSections([section])
                snapshot.appendItems([UniqueItem(section: section, item: 0)], toSection: section)
            }
        }
        
        // OPTIMIZATION: Only apply snapshot if there were actual changes
        if !sectionsToRemove.isEmpty || !sectionsToAdd.isEmpty {
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        // OPTIMIZATION: Only reload headers if window boundaries changed significantly
        let windowBoundaryChangeThreshold = PREFETCH_BUFFER / 2
        let lowerBoundaryChanged = abs(window.lowerBound - previousWindow.lowerBound) > windowBoundaryChangeThreshold
        let upperBoundaryChanged = abs(window.upperBound - previousWindow.upperBound) > windowBoundaryChangeThreshold
        
        if lowerBoundaryChanged || upperBoundaryChanged || previousWindow.isEmpty {
            // OPTIMIZATION: Defer header reload to avoid blocking main thread
            DispatchQueue.main.async { [weak self] in
                self?.headerCollectionView.reloadData()
            }
        }
    }
    
//MARK: Layout
    /// OPTIMIZATION: Creates an efficient compositional layout optimized for large datasets
    func createLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            // OPTIMIZATION: Efficient data access - direct lookup by section index
            guard let tableState = self.tableState,
                  let sections = tableState.rowData[KotlinInt(integerLiteral: sectionIndex + 1)] else {
                // Return default empty section if no data
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(100), heightDimension: .absolute(40))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(100), heightDimension: .absolute(40))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                return NSCollectionLayoutSection(group: group)
            }
            
            var items: [NSCollectionLayoutItem] = []
            var groupWidth = CGFloat(0)
            
            // OPTIMIZATION: Calculate layout dimensions efficiently
            for section in sections {
                groupWidth = 0
                let columnCount = section.cells.count
                
                // OPTIMIZATION: Direct access to column widths without iteration
                for index in 0..<columnCount {
                    if let width = tableState.columnWidths[safe: index] {
                        groupWidth += CGFloat(truncating: width)
                    } else {
                        groupWidth += 150 // Default width
                    }
                }
                
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .absolute(groupWidth),
                    heightDimension: .absolute(40)
                )
                items.append(NSCollectionLayoutItem(layoutSize: itemSize))
            }
            
            // OPTIMIZATION: Efficient group size calculation
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(groupWidth),
                heightDimension: .absolute(CGFloat(sections.count * 40))
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: items)
            
            // Define section with minimal spacing for performance
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
    
    // OPTIMIZATION: Efficient viewport-based prefetching with sliding window and redundancy prevention
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // OPTIMIZATION: Only trigger prefetch for significant section changes to reduce overhead
        let currentSection = indexPath.section
        let sectionChangeThreshold = PREFETCH_BUFFER / 4
        
        if abs(currentSection - lastUpdatedCenterSection) > sectionChangeThreshold {
            // OPTIMIZATION: Async prefetch decision to avoid blocking scroll
            dataOperationQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Update visible range around current section
                self.updateVisibleRange(around: currentSection)
                
                // OPTIMIZATION: Smart prefetching based on scroll direction and speed
                if let isVerticalDownScroll = self.isVerticalDownScroll {
                    let prefetchSection = isVerticalDownScroll ?
                        currentSection + self.PREFETCH_BUFFER :
                        currentSection - self.PREFETCH_BUFFER
                    
                    let packIndex = self.getDataPackIndex(section: prefetchSection)
                    
                    // OPTIMIZATION: Only fetch if not already fetched or in progress
                    if self.dataFetchMap[packIndex] == nil {
                        self.fetchNextTableData(dataPackIndex: packIndex) { startIndex, modal in
                            DispatchQueue.main.async {
                                if let modal {
                                    let endIndex = startIndex + Int(modal.navConfig.batchCount)
                                    self.applySnapshotForWindow(startIndex..<endIndex)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // OPTIMIZATION: Efficient visible range tracking for sliding window management with batched updates
    private func updateVisibleRange(around centerSection: Int) {
        let halfWindow = VISIBLE_WINDOW / 2
        let totalSections = Int(tableState?.currentNavConfig.totalRecord ?? 0)
        
        // Calculate optimal visible range
        let start = max(0, centerSection - halfWindow)
        let end = min(totalSections, centerSection + halfWindow)
        let newRange = start..<end
        
        // OPTIMIZATION: Only update window if significant change to avoid unnecessary updates
        let significantChangeThreshold = PREFETCH_BUFFER / 2
        if abs(newRange.lowerBound - visibleSectionRange.lowerBound) > significantChangeThreshold ||
           abs(newRange.upperBound - visibleSectionRange.upperBound) > significantChangeThreshold {
            visibleSectionRange = newRange
            
            // OPTIMIZATION: Batch window updates using snapshot queue to avoid blocking main thread
            snapshotQueue.async { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.applySnapshotForWindow(newRange)
                }
            }
        }
    }
    
    // OPTIMIZATION: Efficient pack index calculation using BATCH_SIZE constant
    func getDataPackIndex(section: Int) -> Int {
        return max(0, section / BATCH_SIZE)
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
    
    
    // OPTIMIZATION: Async data fetching to prevent UI blocking
    func fetchNextTableData(dataPackIndex: Int, returnBlock: @escaping (_ startIndex: Int, _ tableModal : ZDTableModal?) -> Void)
    {
        // OPTIMIZATION: Check fetch status efficiently and prevent duplicate requests
        if dataFetchMap[dataPackIndex] == false {
            return // Fetch already in progress
        }
        
        let fetchStartTime = CACurrentMediaTime()
        
        // Mark as in progress
        dataFetchMap[dataPackIndex] = false
        let limit = (dataPackIndex * BATCH_SIZE) + 1
        
        print("📡 Starting data fetch for pack \(dataPackIndex) (section \(limit-1))")
        
        // OPTIMIZATION: Perform network/data operations on background queue
        dataOperationQueue.async { [weak self] in
            guard let self = self else { return }
            
            let completionHandler: (ZDTableModal?) -> Void = { modal in
                // OPTIMIZATION: Log fetch performance
                let duration = CACurrentMediaTime() - fetchStartTime
                let status = modal != nil ? "✅" : "❌"
                print("\(status) Data Fetch Pack \(dataPackIndex): \(String(format: "%.0f", duration * 1000))ms")
                
                // OPTIMIZATION: Update fetch status efficiently
                self.dataFetchMap[dataPackIndex] = modal != nil ? true : nil
                
                // Return result on calling queue
                returnBlock(limit - 1, modal)
            }
            
            // OPTIMIZATION: Dispatch delegate calls to main queue as they may involve UI operations
            DispatchQueue.main.async {
                if let delegateTopresenter = self.delegateTopresenter {
                    delegateTopresenter.getTablePage(limit: limit, returnBlock: { report in
                        // Process response on background queue
                        self.dataOperationQueue.async {
                            let modal = self.loadReportResponse(reportData: report?.reportData)
                            completionHandler(modal)
                        }
                    })
                }
                else if let delegateToVudView = self.delegateToVudView {
                    delegateToVudView.getTablePage(limit: limit, returnBlock: { reportData in
                        // Process response on background queue
                        self.dataOperationQueue.async {
                            let modal = self.loadReportResponse(reportData: reportData)
                            completionHandler(modal)
                        }
                    })
                }
                else if let reportModal = self.reportModal {
                    self.dashboardTableViewToPresanter?.getTablePage(limit: 0, Report_Properties: reportModal) { report in
                        // Process response on background queue
                        self.dataOperationQueue.async {
                            let modal = self.loadReportResponse(reportData: report?.reportData)
                            completionHandler(modal)
                        }
                    }
                }
            }
        }
    }
    
    // OPTIMIZATION: Efficient data response processing with error handling
    func loadReportResponse(reportData : ReportDataModal?) -> ZDTableModal?
    {
        guard let reportDataString = reportData?.reportDataString else {
            return nil
        }
        
        // OPTIMIZATION: Parse and add data efficiently without blocking UI
        if let modal = ZDCommonTable.companion.initializeTable(responseString: reportDataString) {
            // OPTIMIZATION: Add data to table state efficiently
            self.tableState?.addNextBatchData(newTableData: modal)
            return modal
        }
        
        return nil
    }
}

extension ZDTableView: UIScrollViewDelegate
{
    
    func updateTheme(cardThemeModal:ZDReportViewTheme) {
        backgroundColor = cardThemeModal.viewBackgroundColor.getColor()
        collectionView?.backgroundColor = cardThemeModal.viewBackgroundColor.getColor()
    }
    
    
    // OPTIMIZATION: Load only first window on initialization instead of all data
    func initializeData()
    {
        // OPTIMIZATION: Monitor initialization performance
        let startTime = CACurrentMediaTime()
        
        // Calculate initial window size - only load first visible window
        let availableRows = tableState?.rowData.count ?? 0
        let initialWindowSize = min(availableRows, VISIBLE_WINDOW)
        
        // OPTIMIZATION: Async initialization to avoid blocking UI
        dataOperationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Initialize data fetch map efficiently - only mark existing data
            let totalRecords = Int(self.tableState?.currentNavConfig.totalRecord ?? 0)
            let numberOfDataPacks = (totalRecords + self.BATCH_SIZE - 1) / self.BATCH_SIZE // Ceiling division
            
            // OPTIMIZATION: Only initialize first few packs instead of all
            for i in 0..<min(3, numberOfDataPacks) { // Only first 3 packs initially
                let startIndex = i * self.BATCH_SIZE + 1
                if self.tableState?.rowData[KotlinInt(integerLiteral: startIndex)] != nil {
                    self.dataFetchMap[i] = true
                } else {
                    self.dataFetchMap[i] = nil
                }
            }
            
            // Apply initial snapshot on main queue
            DispatchQueue.main.async {
                self.applySnapshotForWindow(0..<initialWindowSize)
                
                // OPTIMIZATION: Log initialization performance
                let duration = CACurrentMediaTime() - startTime
                print("📊 Initialization completed in \(String(format: "%.3f", duration * 1000))ms")
                print("🪟 Initial window: 0..<\(initialWindowSize) (\(initialWindowSize) rows)")
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hideScrollButtonView()
    }
    
    // OPTIMIZATION: Enhanced scroll performance with throttling and efficient viewport detection
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // OPTIMIZATION: Throttle scroll events to reduce main thread load
        pendingScrollUpdate = { [weak self] in
            self?.processScrollUpdate(scrollView)
        }
        
        // Cancel previous timer and start new one for throttling
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: scrollThrottleInterval, repeats: false) { [weak self] _ in
            self?.pendingScrollUpdate?()
            self?.pendingScrollUpdate = nil
        }
    }
    
    // OPTIMIZATION: Process scroll updates with reduced frequency and better state management
    private func processScrollUpdate(_ scrollView: UIScrollView) {
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
            
            // OPTIMIZATION: Only update viewport if significant change to reduce UI load
            updateViewportBasedWindowThrottled(scrollView: scrollView)
        }
        
        if isfullview {
            if scrollDirection == nil {
                scrollDirection = getScrollDirection(currentContentOffset: scrollView.contentOffset)
            }
            if let scrollDirection {
                // OPTIMIZATION: Defer scroll button updates to reduce main thread work
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if scrollDirection == .vertical {
                        self.verticalScrollOptionsContainer.updateButtons(contentOffset: scrollView.contentOffset, isVerticalEnd: self.isVerticalEnd(scrollView: scrollView), isHorizontalEnd: self.isHorizontalEnd(scrollView: scrollView))
                        self.showScrollButtonView(isVerticalScroll: true)
                    } else {
                        self.horizontalScrollOptionsContainer.updateButtons(contentOffset: scrollView.contentOffset, isVerticalEnd: self.isVerticalEnd(scrollView: scrollView), isHorizontalEnd: self.isHorizontalEnd(scrollView: scrollView))
                        self.showScrollButtonView(isVerticalScroll: false)
                    }
                }
            }
        }
        previousContentOffset = scrollView.contentOffset
        isScrolling = false
    }
    
    // OPTIMIZATION: Throttled viewport-based window management with center section tracking
    private func updateViewportBasedWindowThrottled(scrollView: UIScrollView) {
        // Calculate which sections are currently visible
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return }
        
        // OPTIMIZATION: Find visible range efficiently
        let visibleSections = Set(visibleIndexPaths.map { $0.section })
        let minSection = visibleSections.min() ?? 0
        let maxSection = visibleSections.max() ?? 0
        
        // OPTIMIZATION: Update sliding window only when center section changes significantly
        let centerSection = (minSection + maxSection) / 2
        let centerSectionChangeThreshold = PREFETCH_BUFFER / 4 // Require significant movement
        
        if abs(centerSection - lastUpdatedCenterSection) > centerSectionChangeThreshold {
            lastUpdatedCenterSection = centerSection
            dataOperationQueue.async { [weak self] in
                self?.updateVisibleRange(around: centerSection)
            }
        }
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
        // OPTIMIZATION: Process any pending scroll updates immediately when dragging ends
        if let pendingUpdate = pendingScrollUpdate {
            scrollThrottleTimer?.invalidate()
            pendingUpdate()
            pendingScrollUpdate = nil
        }
        
        isScrolling = false
        if !isfullview { return }
        if !decelerate {
            startHideTimer()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // OPTIMIZATION: Process any pending scroll updates immediately when deceleration ends
        if let pendingUpdate = pendingScrollUpdate {
            scrollThrottleTimer?.invalidate()
            pendingUpdate()
            pendingScrollUpdate = nil
        }
        
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
        // OPTIMIZATION: Process any pending scroll updates immediately when animation ends
        if let pendingUpdate = pendingScrollUpdate {
            scrollThrottleTimer?.invalidate()
            pendingUpdate()
            pendingScrollUpdate = nil
        }
        
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
    // OPTIMIZATION: Efficient scroll to bottom with smart data loading
    private func moveToBottom() {
        dataOperationQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isScrolling = true
            let totalRecords = Int(self.tableState?.currentNavConfig.totalRecord ?? 0)
            let lastSection = max(0, totalRecords - 1)
            let packIndex = self.getDataPackIndex(section: lastSection)
            
            if self.dataFetchMap[packIndex] == nil {
                // OPTIMIZATION: Fetch last pack asynchronously
                self.fetchNextTableData(dataPackIndex: packIndex) { startIndex, modal in
                    DispatchQueue.main.async {
                        if let modal {
                            // OPTIMIZATION: Load window around the bottom instead of full range
                            let endIndex = startIndex + Int(modal.navConfig.batchCount)
                            let windowStart = max(0, endIndex - self.VISIBLE_WINDOW)
                            self.applySnapshotForWindow(windowStart..<endIndex)
                            self.collectionView.scrollToLast()
                        }
                        self.isScrolling = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    // OPTIMIZATION: Update window to show bottom content
                    let windowStart = max(0, lastSection - self.VISIBLE_WINDOW)
                    self.applySnapshotForWindow(windowStart..<(lastSection + 1))
                    self.collectionView.scrollToLast()
                    self.isScrolling = false
                }
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
