//
//  MainViewController.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/28.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "MainViewController.h"
#import "TTPlayerCache.h"
#import "TTResourceLoaderCache.h"

@interface MainViewController ()<UITableViewDataSource, UITableViewDelegate>
{
    NSString *_selectedUrl;
}

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UILabel *cacheSizeLabel;

@property (nonatomic, strong) NSArray <NSString *> *dataSource;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showCacheSize];
    });
}

- (NSArray<NSString *> *)dataSource {
    if (!_dataSource) {
        ////10+M
        NSString *videoUrl0 = @"http://group.file.dachentech.com.cn/o_1bjrg7i8p40211ad4si1b94c4o4s";
        videoUrl0 = TTResourceUrlFromOrigianllUrl(videoUrl0);
        
        ////20+M
        NSString *videoUrl1 = @"https://video.uning.tv/b8d3c6c8-26e3-11e6-96db-008cfae40bc8/film/6456e3cd-1954-47d3-b7f9-8ca15b1d0227.mp4?s=53760559";
        videoUrl1 = TTResourceUrlFromOrigianllUrl(videoUrl1);
        
        ////7+M
        NSString *videoUrl2 = @"http://7xplva.com2.z0.glb.qiniucdn.com/%E5%BA%8F%E5%88%97%2002_1.mp4";
        videoUrl2 = TTResourceUrlFromOrigianllUrl(videoUrl2);
        
        //// 20+M
        NSString *videoUrl3 = @"http://mp4.22mtv.com:9090/mp45/52596-%E8%90%A7%E7%A3%8A_%E6%A8%8A%E5%B0%91%E5%8D%8E-%E5%A5%BD%E5%85%84%E5%BC%9F%E4%B8%80%E8%BE%88%E5%AD%90[68mtv.com].mp4";
        videoUrl3 = TTResourceUrlFromOrigianllUrl(videoUrl3);
        
        ////200+M
        NSString *videoUrl4 = @"http://mov.bn.netease.com/open-movie/nos/mp4/2015/03/25/SAKKKQR8I_sd.mp4";
        videoUrl4 = TTResourceUrlFromOrigianllUrl(videoUrl4);
        
        _dataSource = @[videoUrl0,videoUrl1,videoUrl2,videoUrl3,videoUrl4];
    }
    return _dataSource;
}

#pragma mark -UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    
    static NSString *cellId = @"cellId";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 0;
    }
    cell.textLabel.text = self.dataSource[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    _selectedUrl = self.dataSource[indexPath.row];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if (!_selectedUrl) {
        _selectedUrl = self.dataSource[0];
    }
    [segue.destinationViewController performSelector:NSSelectorFromString(@"setUrl:") withObject:_selectedUrl];
    [super prepareForSegue:segue sender:sender];
}

- (IBAction)clearLocalCacheBtnAction:(UIButton *)sender {
    [TTResourceLoaderCache clearCache];
    [self showCacheSize];
    [[[UIAlertView alloc] initWithTitle:@"提示" message:@"清除缓存成功" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil] show];
}

- (void)showCacheSize {
    self.cacheSizeLabel.text = [NSString stringWithFormat:@"size:%.2fM",[TTResourceLoaderCache getCacheSize]/1024.0/1024.0];
}

@end
