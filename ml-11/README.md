# 写给程序员的机器学习入门 (十一) - 对象识别 YOLO - 识别人脸位置与是否戴口罩

这篇将会介绍目前最流行的对象识别模型 YOLO，YOLO 的特征是快，识别速度非常快🤗，然而精度相对 Faster-RCNN 只差一点点 (YOLOv3 之后)。阅读这篇需要先了解对象识别的原理，如果你没看过这个系列的前几篇文章 (介绍 RCNN, Fast-RCNN, Faster-RCNN 的文章)，请先阅读它们。

## YOLO 模型概览

YOLO 的缩写是 You only look once，翻译成中文是宝贝你只需要看一次喔😘。YOLO 模型可以直接根据图片输出包含对象的区域与区域对应的分类，一步到位，不像 RCNN 系列的模型需要先计算包含对象的区域，再根据区域判断对应的分类，YOLO 模型的速度比 RCNN 系列的模型要快很多。

YOLO 模型的结构如下：

![01](./01.png)

是不是觉得有点熟悉？看上去就像 Faster-RCNN 的区域生成网络 (RPN) 啊。的确，YOLO 模型原理上就是寻找区域的同时判断区域包含的对象分类，YOLO 模型与区域生成网络有以下的不同：

- YOLO 模型会输出各个区域是否包含**对象中心**，而不是包含对象的一部分
- YOLO 模型会同时输出对象分类
- YOLO 模型输出的区域偏移会根据对象中心点计算，具体算法在下面说明

YOLO 模型与 Faster-RCNN 的区域生成网络最大的不同是会判断各个区域是否包含对象中心，如下图中狗脸覆盖了四个区域，但只有左下角的区域包含了狗脸的中心，YOLO 模型应该只判断这个区域包含对象。

![02](./02.png)

当然，如果对象中心非常接近区域的边界，那么判断起来将会很困难，YOLO 模型在训练的时候会忽略对象重叠率高于一定水平的区域，具体可以参考后面给出的代码。

YOLO 模型会针对各个区域输出以下的结果，这里假设有三个分类：

- 是否包含对象中心 (是为 1, 否为 0)
- 区域偏移 x
- 区域偏移 y
- 区域偏移 w
- 区域偏移 h
- 分类 1 的可能性 (0 ~ 1)
- 分类 2 的可能性 (0 ~ 1)
- 分类 3 的可能性 (0 ~ 1)

输出结果的维度是 `批次大小, 区域数量, 5 + 分类数量`。

区域偏移用于调整输出的区域范围，例如上图中狗脸的中心点大约在区域的右上角，如果把区域左上角看作 (0, 0)，右下角看作 (1, 1)，那么狗脸中心点应该在 (0.95, 0.1) 的位置，而狗脸大小相对于区域长宽大概是 (1.3, 1.5) 倍，生成训练数据的时候会根据这 4 个值计算区域偏移，具体计算代码在下面给出。

![03](./03.png)

看到这里你可能会想，YOLO 模型看起来很简单啊，我可以丢掉操蛋的 Faster-RCNN 模型了🤢。不，没那么简单，以上介绍的只是 YOLO**v1** 模型，YOLOv1 模型的精度非常低，后面为了改进识别精度还发展出 YOLOv2, YOLOv3, YOLOv4, YOLOv5 模型😮，接下来将会介绍 YOLOv2, YOLOv3 模型主要改进了什么部分，再给出 YOLOv3 模型的实现。YOLOv4 和 YOLOv5 模型主要改进了提取特征用的 CNN 模型 (也称骨干网络 Backbone Network)，原始的 YOLO 模型使用了 C 语言编写的 Darknet 作为骨干网络，而这篇使用 Resnet 作为骨干网络，所以只介绍到 YOLOv3。

### YOLOv2

YOLOv2 最主要的改进点是引入了锚点 (Anchor)，如果你已经看完前几篇文章那么应该很了解锚点是什么，锚点会从每个区域的中心点衍生出不同形状的多个锚点区域：

![04](./04.png)

Faster-RCNN 使用锚点主要为了提升区域重叠率以避免漏掉部分对象 (Faster-RCNN 训练时会根据重叠率判断区域是否包含对象，如果对象很长或者很宽但形状只有正方形，那么重叠率就会比较低导致该对象被漏掉)，然而 YOLO 使用对象中心点，并不会存在因重叠率不足而漏掉对象的问题，YOLO 使用锚点是为了支持识别中心位于同一个区域的多个对象，如下图所示：

![05](./05.png)

如果对象中心落在某个区域，YOLO 会计算该区域对应的各个形状的重叠率，并使用重叠率最高的形状，这样如果多个对象中心落在同一个区域但它们的形状不同，就会分别判断出不同的分类。YOLOv2 的输出如下图所示：

![06](./06.png)

输出结果的维度是 `批次大小, 区域数量 * 形状数量, 5 + 分类数量`。

YOLOv2 还有一些针对骨干网络和训练方法的改进点，但这篇文章都没用到所以就不介绍了，如果你有兴趣可以参考后面给出的论文链接。

你可能会注意到 YOLO 划分的区域是固定的，并且判断区域是否存在对象和对象的分类时只会使用该区域中的数据，这样会导致以下的问题：

- 如果对象相对区域过大，则模型很难确定哪个区域包含中心点
    - Faster-RCNN 按锚点区域的重叠率而不是中心点判断是否包含对象，所以不会有这个问题
- 如果对象相对区域过大，则每个区域都只包含对象的一小部分，很难依据这一小部分来判断对象分类 (例如区域只包含鼻子的时候模型需要只根据鼻子判断是否人脸)
    - Faster-RCNN 分两步走，标签分类网络会根据区域生成网络给出的区域截取特征再判断分类，所以不会有这个问题
- 如果对象相对区域过小，则多个对象有可能处于同一个区域中
    - 因为 Faster-RCNN 不会有以上两个问题，所以可以用更小的区域

![07](./07.png)

因此，YOLOv2 只适合对象大小和区域大小比较接近的场景。

### YOLOv3

为了更好的支持不同大小的对象，YOLOv3 引入了多尺度检测机制 (Multi-Scale Detection)，这个机制可以说是 YOLO 模型的精华，引入这个机制之前 YOLO 模型的精度很不理想，而引入之后 YOLO 模型达到了接近 Faster-RCNN 的精度，并且速度还是比 Faster-RCNN 要快。

多尺度检测机制简单的来说就是按不同的尺度划分区域，然后再检测这些不同大小的区域是否包含对象，**检测的时候大区域的特征会混合到小区域中**，使得小区域判断时拥有一定程度的上下文信息。

![08](./08.png)

实现多尺度检测机制首先要让 CNN 模型输出不同尺度的特征，我们之前已经看过 CNN 模型中的卷积层可以输出比原有大小更小的特征 (参考第 8 篇)，例如指定内核大小 (kernel_size) 为 3，处理间隔 (stride) 为 2，填充大小 (padding) 为 1 的时候，输出大小刚好是输入大小的一半，把这样的卷积层放到 CNN 模型的末尾，然后保留各个卷积层的输出，就可以得出不同尺度的特征。例如指定 3 个尺度的时候，可能会得到以下大小的 3 个特征：

- 批次大小, 通道数量, 8, 8
- 批次大小, 通道数量, 4, 4
- 批次大小, 通道数量, 2, 2

之后再反向处理这三个特征，首先把 `批次大小, 通道数量, 2, 2` 交给进一步处理特征的 CNN 模型，这个模型会让输出长宽等于输入长宽，所以输出大小和原有大小相同，再扩大特征到 `批次大小, 通道数量, 4, 4`，例如：

``` text
a b
c d
```

扩大以后会变为


``` text
a a b b
a a b b
c c d d
c c d d
```

之后再合并这个特征到大小为 `批次大小, 通道数量, 4, 4` 的特征，得出 `批次大小, 通道数量 * 2, 4, 4` 的特征，把这个特征交给进一步处理特征的 CNN 模型，之后的流程就如上图所示了，最终会得出以下大小的 3 个结果：

- 批次大小, 形状数量 * (5 + 分类数量), 8, 8
- 批次大小, 形状数量 * (5 + 分类数量), 4, 4
- 批次大小, 形状数量 * (5 + 分类数量), 2, 2

变形以后得出：

- 批次大小, 8 * 8 * 形状数量, 5 + 分类数量
- 批次大小, 4 * 4 * 形状数量, 5 + 分类数量
- 批次大小, 2 * 2 * 形状数量, 5 + 分类数量

总结起来，YOLOv3 模型的结构如下图所示：

![09](./09.png)

## YOLO 模型的实现

接下来我们来看看 YOLO 模型的实现细节，后面会给出完整代码。注意这篇的实现与官方实现不完全一样🤕，这篇会用 Resnet 作为骨干网络，并且会以识别人脸位置为目标调整参数。

### 定义锚点 (Anchor)

首先是生成锚点范围列表，代码看起来和 Faster-RCNN 使用的差不多：

``` python
IMAGE_SIZE = (256, 256) # 缩放图片的大小

Anchors = None # 锚点列表，包含 锚点数量 * 形状数量 的范围
AnchorSpans = (16, 32, 64) # 尺度列表，值为锚点之间的距离
AnchorAspects = ((1, 1), (1, 2), (2, 1)) # 锚点对应区域的长宽比例列表

def generate_anchors():
    """根据锚点和形状生成锚点范围列表"""
    w, h = IMAGE_SIZE
    anchors = []
    for span in AnchorSpans:
        for x in range(0, w, span):
            for y in range(0, h, span):
                xcenter, ycenter = x + span / 2, y + span / 2
                for ratio in AnchorAspects:
                    ww = span * ratio[0]
                    hh = span * ratio[1]
                    xx = xcenter - ww / 2
                    yy = ycenter - hh / 2
                    xx = max(int(xx), 0)
                    yy = max(int(yy), 0)
                    ww = min(int(ww), w - xx)
                    hh = min(int(hh), h - yy)
                    anchors.append((xx, yy, ww, hh))
    return anchors

Anchors = generate_anchors()
```
但 YOLO 需要分别处理每个尺度，所以生成的锚点范围列表会首先按尺度排序，生成出来的结构如下：

``` text
[
    尺度1区域1形状1的范围,
    尺度1区域1形状2的范围,
    尺度1区域1形状3的范围,
    尺度1区域2形状1的范围,
    尺度1区域2形状2的范围,
    尺度1区域2形状3的范围,
    ...
    尺度2区域1形状1的范围,
    尺度2区域1形状2的范围,
    尺度2区域1形状3的范围,
    ...
    尺度3区域1形状1的范围,
    尺度3区域1形状2的范围,
    尺度3区域1形状3的范围,
    ...
]
```

最终会包含 `(256/16)^2*3 + (256/32)^2*3 + (256/64)^2*3 = 768 + 192 + 48 = 1008` 个锚点范围。

这篇文章会用 YOLO 模型实现识别人脸位置与是否带口罩，而人脸的形状通常接近 1:1，所以下面的代码会使用以下的参数生成锚点范围列表：

``` python
AnchorSpans = (16, 32, 64) # 尺度列表，值为锚点之间的距离
AnchorAspects = ((1, 1), (1.5, 1.5)) # 锚点对应区域的长宽比例列表
```

如果你想用来检测其他物体，可以修改参数使得锚点范围的形状更匹配物体形状，以提升检测率。

### 调整区域范围的算法

在有了锚点范围之后，我们还需要决定一个把锚点范围调整到物体范围的算法，一共需要四个参数，计算规则如下：

- 区域偏移 x: 物体的中心点在锚点范围中的 x 轴位置，0~1 之间
- 区域偏移 y: 物体的中心点在锚点范围中的 y 轴位置，0~1 之间
- 区域偏移 w: log(物体的长度与锚点范围长度的比例)
- 区域偏移 h: log(物体的高度与锚点范围高度的比例)

![10](./10.png)

看起来比较简单吧😎，需要注意的是这样调整出来的物体范围中心点一定会在锚点范围中，这点跟 Faster-RCNN 使用的算法不一样。

以下是计算使用的代码，注释中的 "实际区域" 代表物体范围，"候选区域" 代表锚点范围。

``` python
def calc_box_offset(candidate_box, true_box):
    """计算候选区域与实际区域的偏移值，要求实际区域的中心点必须在候选区域中"""
    # 计算实际区域的中心点在候选区域中的位置，范围会在 0 ~ 1 之间
    x1, y1, w1, h1 = candidate_box
    x2, y2, w2, h2 = true_box
    x_offset = ((x2 + w2 // 2) - x1) / w1
    y_offset = ((y2 + h2 // 2) - y1) / h1
    # 计算实际区域长宽相对于候选区域长宽的比例，使用 log 减少过大的值
    w_offset = math.log(w2 / w1)
    h_offset = math.log(h2 / h1)
    return (x_offset, y_offset, w_offset, h_offset)

def adjust_box_by_offset(candidate_box, offset):
    """根据偏移值调整候选区域"""
    x1, y1, w1, h1 = candidate_box
    x_offset, y_offset, w_offset, h_offset = offset
    w2 = math.exp(w_offset) * w1
    h2 = math.exp(h_offset) * h1
    x2 = x1 + w1 * x_offset - w2 // 2
    y2 = y1 + h1 * y_offset - h2 // 2
    x2 = min(IMAGE_SIZE[0]-1,  x2)
    y2 = min(IMAGE_SIZE[1]-1,  y2)
    w2 = min(IMAGE_SIZE[0]-x2, w2)
    h2 = min(IMAGE_SIZE[1]-y2, h2)
    return (x2, y2, w2, h2)
```

### 生成用于训练的实际输出

决定了锚点与调整区域范围的算法以后，我们可以根据训练使用的数据集生成实际的输出结果，训练使用的数据集需要包含：

- 图片
- 包含的对象，可以有多个
    - 对象的范围
    - 对象的分类

数据集准备好以后，我们比对锚点范围列表与数据集中对象的范围，然后针对每张图片的每个锚点范围生成以下数据：

- 是否对象
- 区域偏移 x
- 区域偏移 y
- 区域偏移 w
- 区域偏移 h
- 分类 1 的可能性
- 分类 2 的可能性
- 分类 3 的可能性

是否对象只有 0 或 1 两个值，如果锚点范围包含对象中心并且锚点范围与对象范围的重叠率 (IOU) 大于阈值 (例如 30%)，则为 1，否则为 0。注意如果是否对象为 0，那么后面的区域偏移和各个分类的可能性不需要计算 (例如设置为 0)，计算损失的时候也会除掉它们。

四个区域偏移会根据锚点范围与对象范围计算，算法参考上面的说明。

各个分类的可能性按对象的分类计算，如果对象的分类为 "人"，而三个分类分别为 "人 猫 狗" 那么分类 1 的可能性为 1，分类 2 与分类 3 的可能性为 0。此外 YOLO 还支持多分类 (要求计算损失的时候用 BinaryCrossEntropy)，如果分类为 "人 男人 女人 猪 公猪 母猪" 并且对象是 "母猪" 时，那么各个分类的可能性就是 "0 0 0 1 0 1"。需要注意这里计算出来的值是供模型学习的，模型学习完以后可能会输出 "0.9 0.2 0.0" 这样的浮点数，需要判断最大的值找出最可能的分类，并且根据值的大小判断模型对结果有多少把握。

如果你记得前一篇介绍 Faster-RCNN 模型的文章，应该会想到有一个表示 "非对象" 的分类，Faster-RCNN 的区域生成网络首先会判断一次是否对象，之后的标签分类网络会再次去掉归为非对象分类的结果，这样的做法让识别的精度提升了很多。然而 YOLO 模型只有单步，原则上是不需要非对象分类的，即使加上非对象分类也不会提升判断 "是否对象" 的精度。但如果数据量不足，添加非对象分类可以帮助更好的识别分类。举个例子，例如图片中有棕色的猫和红色的猪，模型可能会判断棕色的都是猫，红色的都是猪，但添加非对象分类以后，如果图片还包含棕色的凳子和红色的电饭锅，那么模型就不会只根据颜色来判断。因此，下面识别人脸位置的例子会添加非对象分类。

具体的代码参考后面的 prepare 函数吧🤒。

### 计算特征

原始的 YOLO 模型计算特征使用的是叫做 Darknet 的网络，这个网络是 YOLO 作者用 C 语言实现的，算是 YOLO 作者对自己写的框架的宣传吧😤。不过只要理解 YOLO 模型的原理，用其他网络也可以实现差不多的效果 (虽然作者为了刷分做出了很多调整，只是套用其他网络的话正确度追不上)，这里我用了目前用的最广泛的 Resnet 模型，代码如下：

``` python
self.previous_channels_out = 4
self.resnet_models = nn.ModuleList([
    nn.Sequential(
        nn.Conv2d(3, self.previous_channels_out, kernel_size=3, stride=1, padding=1, bias=False),
        nn.BatchNorm2d(self.previous_channels_out),
        nn.ReLU(inplace=True),
        self._make_layer(BasicBlock, channels_out=16, num_blocks=2, stride=1),
        self._make_layer(BasicBlock, channels_out=32, num_blocks=2, stride=2),
        self._make_layer(BasicBlock, channels_out=64, num_blocks=2, stride=2),
        self._make_layer(BasicBlock, channels_out=128, num_blocks=2, stride=2),
        self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2)),
    self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2),
    self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2)
])
```

`_make_layer` 与 `BasicBlock` 的代码和之前文章给出的一样，你也可以参考下面的完整代码。

这里定义的 `resnet_models` 包含了三个子模型，第一个模型会输出维度为 `批次大小,256,图片宽度/16,图片高度/16` 的结果，第二个模型会接收第一个模型的结果然后输出维度为 `批次大小,256,图片宽度/32,图片高度/32` 的结果，第三个模型会接收第二个模型的结果然后输出维度为 `批次大小,256,图片宽度/64,图片高度/64` 的结果。这三个结果分别代表把图片分割为 `16x16`，`32x32`，`64x64` 个区域以后，各个区域对应的特征。

输出三个特征的使用的代码如下：

``` python
def forward(self, x):
    features_list = []
    resnet_input = x
    for m in self.resnet_models:
        resnet_input = m(resnet_input)
        features_list.append(resnet_input)
```

### 根据特征预测输出

上一步我们得出了三个特征，接下来就可以根据这三个特征预测三个尺度中的各个区域是否包含对象与对象的分类了。流程和上面介绍的一样，需要分成三步：

- 进一步处理特征 (长宽不变)
- 扩大特征长宽，并且合并到下一个尺度 (更细的尺度) 的特征
- 判断是否对象中心与标签分类

模型代码：

``` python
self.yolo_detectors = nn.ModuleList([
    # 进一步处理特征
    nn.ModuleList([nn.Sequential(
        nn.Conv2d(256 if index == 0 else 512, 256, kernel_size=1, stride=1, padding=0, bias=True),
        nn.ReLU(inplace=True),
        nn.Conv2d(256, 512, kernel_size=3, stride=1, padding=1, bias=True),
        nn.ReLU(inplace=True),
        nn.Conv2d(512, 256, kernel_size=1, stride=1, padding=0, bias=True),
        nn.ReLU(inplace=True)),
    # 扩大特征长宽
    nn.Upsample(scale_factor=2, mode="nearest"),
    # 判断是否对象中心与标签分类
    nn.Sequential(
        nn.Conv2d(256, 512, kernel_size=3, stride=1, padding=1, bias=True),
        nn.ReLU(inplace=True),
        nn.Conv2d(512, 256, kernel_size=3, stride=1, padding=1, bias=True),
        nn.ReLU(inplace=True),
        nn.Conv2d(256, MyModel.AnchorTotalOutputs, kernel_size=1, stride=1, padding=0, bias=True))])
    for index in range(len(self.resnet_models))
])
```

"判断是否对象中心与标签分类" 的部分可以用 CNN 模型也可以用线性模型，多个不改变长宽的卷积层组合起来可以做到与多层线性模型接近的效果。如果用 CNN 模型可以把维度是 `(B, C, W, H)` 的输入转换到维度是 `(B, O, W, H)` 的结果，如果用线性模型则需要先把输入变形到 `(B*W*H, C)` 然后再通过线性模型转换到维度是 `(B*W*H, O)` 的结果，再变形到 `(B, O, W, H)`。前一篇文章介绍的 Faster-RCNN 实现用了线性模型，而这篇使用 CNN 模型，原则上用哪种都可以🤒。

处理特征的代码：

``` python
previous_upsampled_feature = None
outputs = []
for index, feature in enumerate(reversed(features_list)):
    if previous_upsampled_feature is not None:
        # 合并大的锚点距离抽取的特征到小的锚点距离抽取的特征
        feature = torch.cat((feature, previous_upsampled_feature), dim=1)
    # 计算用于合并的特征
    hidden = self.yolo_detectors[index][0](feature)
    # 放大特征 (用于下一次处理时合并)
    upsampled = self.yolo_detectors[index][1](hidden)
    # 计算最终的预测输出
    output = self.yolo_detectors[index][2](hidden)
    previous_upsampled_feature = upsampled
    outputs.append(output)
```

之后 `outputs` 会包含三个结果，维度是 `(批次大小, (5+分类数量)*形状数量, 尺度对应的宽度, 尺度对应的高度)`，把这三个结果连起来数量会刚好等于之前生成的锚点数量。连接三个结果的代码如下，注意顺序需要与生成锚点时使用的顺序一样，这样连接后的结果和锚点范围就可以有一对一的关系。

``` python
outputs_flatten = []
# 前面处理特征的时候用了 reversed，这里需要再次用 reversed 把顺序调换回来
# 调换以后的三个结果顺序应该与 AnchorSpans 一致
for output in reversed(outputs):
    # 变形到 (批次大小, 尺度对应的宽度, 尺度对应的高度, (5+分类数量)*形状数量)
    output = output.permute(0, 2, 3, 1)
    # 变形到 (批次大小, 宽度*高度*形状数量, 5+分类数量)
    # 生成锚点时使用的顺序是 宽度 => 高度 => 形状
    output = output.reshape(output.shape[0], -1, MyModel.AnchorOutputs)
    outputs_flatten.append(output)
# 连接以后维度是 (批次大小, 尺度数量*宽度*高度*形状数量, 5+分类数量)
# 即 (批次大小, 锚点数量, 5+分类数量)
outputs_all = torch.cat(outputs_flatten, dim=1)
```

在返回 outputs_all 之前，还需要用 sigmoid 来让是否对象中心与各个分类的可能性对应的值落在 0 ~ 1 之间。注意部分 YOLO 的实现会用 sigmoid 来处理区域偏移 x 和区域偏移 y，因为这两个值也应该落在 0 ~ 1 之间，但我个人认为 sigmoid 只适合处理预期结果是二进制 (0 或 1) 的值，而区域偏移预期结果平均分布在 0 ~ 1 之间，不能起到归并的作用，效果会跟 hardtanh 差不多。

``` python
# 是否对象中心应该在 0 ~ 1 之间，使用 sigmoid 处理
outputs_all[:,:,:1] = self.sigmoid(outputs_all[:,:,:1])
# 分类应该在 0 ~ 1 之间，使用 sigmoid 处理
outputs_all[:,:,5:] = self.sigmoid(outputs_all[:,:,5:])
```

处理完以后，`outputs_all` 就是 YOLO 模型返回的结果了，它在训练的时候会用于计算损失并调整参数，在实际预测的时候会配合之前生成的锚点列表得出包含对象的区域与对象分类，并标记到图片或者视频上。

### 计算损失

又到计算损失的时间了😩，YOLO 的预测输出和实际输出维度是一样的，但我们不能只用一个损失函数来计算它们，YOLO 同样需要计算多个损失并合并它们。

首先我们需要区分正样本 (包含对象中心的区域) 和负样本 (不包含对象中心的区域)，方法在前面也提到过了：

- 正样本：包含对象中心并且重叠率大于某个阈值
- 负样本：不包含对象中心并且与任意对象的重叠率均小于某个阈值

负样本要求重叠率低于阈值是为了照顾对象中心非常接近区域边缘的对象，这时模型很难判断对象中心具体在哪个区域，把这些样本从负样本中排除掉可以帮助模型更容易的学习，最终模型可以判断对象中心在相邻的两个区域但不会被调整。

YOLO 模型会计算与合并以下的损失：

- 正样本的是否对象中心，使用 MSELoss
- 负样本的是否对象中心 * 0.5，使用 MSELoss
    - 因为大部分区域不包含对象中心，这里乘以 0.5 以减少负样本的损失对调整参数的影响
- 正样本的区域偏移，使用 MSELoss
    - 非正样本的区域偏移会被忽略，计算起来没意义
- 正样本的标签分类损失，使用 BCELoss
    - BinaryCrossEntropy 损失函数支持多分类，虽然本篇的例子只有单分类
- 如果有非对象分类，则计算负样本的标签分类损失，使用 BCELoss
    - 如果不使用非对象分类，则不需要计算

具体计算代码如下：

``` python
def loss_function(predicted, actual):
    """YOLO 使用的多任务损失计算器"""
    result_tensor, result_isobject_masks, result_nonobject_masks = actual
    objectness_losses = []
    offsets_losses = []
    labels_losses = []
    for x in range(result_tensor.shape[0]):
        mask_positive = result_isobject_masks[x]
        mask_negative = result_nonobject_masks[x]
        # 计算是否对象中心的损失，分别针对正负样本计算
        # 因为大部分区域不包含对象中心，这里减少负样本的损失对调整参数的影响
        objectness_loss_positive = nn.functional.mse_loss(
            predicted[x,mask_positive,0], result_tensor[x,mask_positive,0])
        objectness_loss_negative = nn.functional.mse_loss(
            predicted[x,mask_negative,0], result_tensor[x,mask_negative,0]) * 0.5
        objectness_losses.append(objectness_loss_positive)
        objectness_losses.append(objectness_loss_negative)
        # 计算区域偏移的损失，只针对正样本计算
        offsets_loss = nn.functional.mse_loss(
            predicted[x,mask_positive,1:5], result_tensor[x,mask_positive,1:5])
        offsets_losses.append(offsets_loss)
        # 计算标签分类的损失，分别针对正负样本计算
        labels_loss_positive = nn.functional.binary_cross_entropy(
            predicted[x,mask_positive,5:], result_tensor[x,mask_positive,5:])
        labels_loss_negative = nn.functional.binary_cross_entropy(
            predicted[x,mask_negative,5:], result_tensor[x,mask_negative,5:]) * 0.5
        labels_losses.append(labels_loss_positive)
        labels_losses.append(labels_loss_negative)
    loss = (
        torch.mean(torch.stack(objectness_losses)) +
        torch.mean(torch.stack(offsets_losses)) +
        torch.mean(torch.stack(labels_losses)))
    return loss
```

### 合并结果区域

最后就是把 YOLO 模型返回的预测结果转换到具体的区域列表了，算法是前几篇介绍过的 NMS 算法，代码如下：

``` python
ObjScoreThreshold = 0.9 # 认为是对象中心所需要的最小分数
IOUMergeThreshold = 0.3 # 判断是否应该合并重叠区域的重叠率阈值

def convert_predicted_result(predicted):
    """转换预测结果到 (标签, 区域, 对象中心分数, 标签识别分数) 的列表，重叠区域使用 NMS 算法合并"""
    # 记录重叠的结果区域, 结果是 [ [(标签, 区域, RPN 分数, 标签识别分数)], ... ]
    final_result = []
    for anchor, tensor in zip(Anchors, predicted):
        obj_score = tensor[0].item()
        if obj_score <= ObjScoreThreshold:
            # 要求对象中心分数超过一定值
            continue
        offset = tensor[1:5].tolist()
        offset[0] = max(min(offset[0], 1), 0) # 中心点 x 的偏移应该在 0 ~ 1 之间
        offset[1] = max(min(offset[1], 1), 0) # 中心点 y 的偏移应该在 0 ~ 1 之间
        box = adjust_box_by_offset(anchor, offset)
        label_max = tensor[5:].max(dim=0)
        cls_score = label_max.values.item()
        label = label_max.indices.item()
        if label == 0:
            # 跳过非对象分类
            continue
        for index in range(len(final_result)):
            exists_results = final_result[index]
            if any(calc_iou(box, r[1]) > IOUMergeThreshold for r in exists_results):
                exists_results.append((label, box, obj_score, cls_score))
                break
        else:
            final_result.append([(label, box, obj_score, cls_score)])
    # 合并重叠的结果区域 (使用 对象中心分数 * 标签识别分数 最高的区域为结果区域)
    for index in range(len(final_result)):
        exists_results = final_result[index]
        exists_results.sort(key=lambda r: r[2]*r[3])
        final_result[index] = exists_results[-1]
    return final_result
```

这篇的例子用了非对象分类，所以会跳过非对象分类的区域，如果不使用则不需要这样处理。

## YOLO 模型的论文

如果你想看原始的 YOLO 论文可以点下面的链接🤒，很难喔：

- YOLO: https://arxiv.org/pdf/1506.02640.pdf
- YOLOv2: https://arxiv.org/pdf/1612.08242.pdf (这篇同时介绍了怎样预测 9000 多个分类的方法)
- YOLOv3: https://arxiv.org/pdf/1804.02767.pdf

## 使用 YOLO 模型识别人脸位置与是否戴口罩

接下来我们用 YOLO 模型把没带口罩的家伙抓出来吧🤗，和上一篇一样会用两个数据集。

https://www.kaggle.com/andrewmvd/face-mask-detection

这个数据集包含了 853 张图片 (部分图片没有使用)，其中各个分类的数量如下：

- 戴口罩的区域 (with_mask): 3232 个
- 不戴口罩的区域 (without_mask): 717 个
- 带了口罩但姿势不正确的区域 (mask_weared_incorrect): 123 个

因为带了口罩但姿势不正确的样本数量很少，所以都归到戴口罩里面去😠。

https://www.kaggle.com/vin1234/count-the-number-of-faces-present-in-an-image

这个数据集一共有 24533 个区域，都是不戴口罩的。

加起来数量如下：

- 戴口罩的区域 (with_mask): 3232+123=3355 个
- 不戴口罩的区域 (without_mask): 717+24533 = 25250 个

使用这个数据集训练，并且训练成功以后使用模型识别图片或视频的完整代码如下：

``` python
import os
import sys
import torch
import gzip
import itertools
import random
import numpy
import math
import pandas
import json
from PIL import Image
from PIL import ImageDraw
from PIL import ImageFont
from torch import nn
from matplotlib import pyplot
from collections import defaultdict
from collections import deque
import xml.etree.cElementTree as ET

# 缩放图片的大小
IMAGE_SIZE = (256, 192)
# 训练使用的数据集路径
DATASET_1_IMAGE_DIR = "./archive/images"
DATASET_1_ANNOTATION_DIR = "./archive/annotations"
DATASET_2_IMAGE_DIR = "./784145_1347673_bundle_archive/train/image_data"
DATASET_2_BOX_CSV_PATH = "./784145_1347673_bundle_archive/train/bbox_train.csv"
# 分类列表
# YOLO 原则上不需要 other 分类，但实测中添加这个分类有助于提升标签分类的精确度
CLASSES = [ "other", "with_mask", "without_mask" ]
CLASSES_MAPPING = { c: index for index, c in enumerate(CLASSES) }
# 判断是否存在对象使用的区域重叠率的阈值 (另外要求对象中心在区域内)
IOU_POSITIVE_THRESHOLD = 0.30
IOU_NEGATIVE_THRESHOLD = 0.30

# 用于启用 GPU 支持
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class BasicBlock(nn.Module):
    """ResNet 使用的基础块"""
    expansion = 1 # 定义这个块的实际出通道是 channels_out 的几倍，这里的实现固定是一倍
    def __init__(self, channels_in, channels_out, stride):
        super().__init__()
        # 生成 3x3 的卷积层
        # 处理间隔 stride = 1 时，输出的长宽会等于输入的长宽，例如 (32-3+2)//1+1 == 32
        # 处理间隔 stride = 2 时，输出的长宽会等于输入的长宽的一半，例如 (32-3+2)//2+1 == 16
        # 此外 resnet 的 3x3 卷积层不使用偏移值 bias
        self.conv1 = nn.Sequential(
            nn.Conv2d(channels_in, channels_out, kernel_size=3, stride=stride, padding=1, bias=False),
            nn.BatchNorm2d(channels_out))
        # 再定义一个让输出和输入维度相同的 3x3 卷积层
        self.conv2 = nn.Sequential(
            nn.Conv2d(channels_out, channels_out, kernel_size=3, stride=1, padding=1, bias=False),
            nn.BatchNorm2d(channels_out))
        # 让原始输入和输出相加的时候，需要维度一致，如果维度不一致则需要整合
        self.identity = nn.Sequential()
        if stride != 1 or channels_in != channels_out * self.expansion:
            self.identity = nn.Sequential(
                nn.Conv2d(channels_in, channels_out * self.expansion, kernel_size=1, stride=stride, bias=False),
                nn.BatchNorm2d(channels_out * self.expansion))

    def forward(self, x):
        # x => conv1 => relu => conv2 => + => relu
        # |                              ^
        # |==============================|
        tmp = self.conv1(x)
        tmp = nn.functional.relu(tmp, inplace=True)
        tmp = self.conv2(tmp)
        tmp += self.identity(x)
        y = nn.functional.relu(tmp, inplace=True)
        return y

class MyModel(nn.Module):
    """YOLO (基于 ResNet 的变种)"""
    Anchors = None # 锚点列表，包含 锚点数量 * 形状数量 的范围
    AnchorSpans = (16, 32, 64) # 尺度列表，值为锚点之间的距离
    AnchorAspects = ((1, 1), (1.5, 1.5)) # 锚点对应区域的长宽比例列表
    AnchorOutputs = 1 + 4 + len(CLASSES) # 每个锚点范围对应的输出数量，是否对象中心 (1) + 区域偏移 (4) + 分类数量
    AnchorTotalOutputs = AnchorOutputs * len(AnchorAspects) # 每个锚点对应的输出数量
    ObjScoreThreshold = 0.9 # 认为是对象中心所需要的最小分数
    IOUMergeThreshold = 0.3 # 判断是否应该合并重叠区域的重叠率阈值

    def __init__(self):
        super().__init__()
        # 抽取图片特征的 ResNet
        # 因为锚点距离有三个，这里最后会输出各个锚点距离对应的特征
        self.previous_channels_out = 4
        self.resnet_models = nn.ModuleList([
            nn.Sequential(
                nn.Conv2d(3, self.previous_channels_out, kernel_size=3, stride=1, padding=1, bias=False),
                nn.BatchNorm2d(self.previous_channels_out),
                nn.ReLU(inplace=True),
                self._make_layer(BasicBlock, channels_out=16, num_blocks=2, stride=1),
                self._make_layer(BasicBlock, channels_out=32, num_blocks=2, stride=2),
                self._make_layer(BasicBlock, channels_out=64, num_blocks=2, stride=2),
                self._make_layer(BasicBlock, channels_out=128, num_blocks=2, stride=2),
                self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2)),
            self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2),
            self._make_layer(BasicBlock, channels_out=256, num_blocks=2, stride=2)
        ])
        # 根据各个锚点距离对应的特征预测输出的卷积层
        # 大的锚点距离抽取的特征会合并到小的锚点距离抽取的特征
        # 这里的三个子模型意义分别是:
        # - 计算用于合并的特征
        # - 放大特征
        # - 计算最终的预测输出
        self.yolo_detectors = nn.ModuleList([
            nn.ModuleList([nn.Sequential(
                nn.Conv2d(256 if index == 0 else 512, 256, kernel_size=1, stride=1, padding=0, bias=True),
                nn.ReLU(inplace=True),
                nn.Conv2d(256, 512, kernel_size=3, stride=1, padding=1, bias=True),
                nn.ReLU(inplace=True),
                nn.Conv2d(512, 256, kernel_size=1, stride=1, padding=0, bias=True),
                nn.ReLU(inplace=True)),
            nn.Upsample(scale_factor=2, mode="nearest"),
            nn.Sequential(
                nn.Conv2d(256, 512, kernel_size=3, stride=1, padding=1, bias=True),
                nn.ReLU(inplace=True),
                nn.Conv2d(512, 256, kernel_size=3, stride=1, padding=1, bias=True),
                nn.ReLU(inplace=True),
                nn.Conv2d(256, MyModel.AnchorTotalOutputs, kernel_size=1, stride=1, padding=0, bias=True))])
            for index in range(len(self.resnet_models))
        ])
        # 处理结果范围的函数
        self.sigmoid = nn.Sigmoid()

    def _make_layer(self, block_type, channels_out, num_blocks, stride):
        """创建 resnet 使用的层"""
        blocks = []
        # 添加第一个块
        blocks.append(block_type(self.previous_channels_out, channels_out, stride))
        self.previous_channels_out = channels_out * block_type.expansion
        # 添加剩余的块，剩余的块固定处理间隔为 1，不会改变长宽
        for _ in range(num_blocks-1):
            blocks.append(block_type(self.previous_channels_out, self.previous_channels_out, 1))
            self.previous_channels_out *= block_type.expansion
        return nn.Sequential(*blocks)

    @staticmethod
    def _generate_anchors():
        """根据锚点和形状生成锚点范围列表"""
        w, h = IMAGE_SIZE
        anchors = []
        for span in MyModel.AnchorSpans:
            for x in range(0, w, span):
                for y in range(0, h, span):
                    xcenter, ycenter = x + span / 2, y + span / 2
                    for ratio in MyModel.AnchorAspects:
                        ww = span * ratio[0]
                        hh = span * ratio[1]
                        xx = xcenter - ww / 2
                        yy = ycenter - hh / 2
                        xx = max(int(xx), 0)
                        yy = max(int(yy), 0)
                        ww = min(int(ww), w - xx)
                        hh = min(int(hh), h - yy)
                        anchors.append((xx, yy, ww, hh))
        return anchors

    def forward(self, x):
        # 抽取各个锚点距离对应的特征
        # 维度分别是:
        # torch.Size([16, 256, 16, 12])
        # torch.Size([16, 256, 8, 6])
        # torch.Size([16, 256, 4, 3])
        features_list = []
        resnet_input = x
        for m in self.resnet_models:
            resnet_input = m(resnet_input)
            features_list.append(resnet_input)
        # 根据特征预测输出
        # 维度分别是:
        # torch.Size([16, 16, 4, 3])
        # torch.Size([16, 16, 8, 6])
        # torch.Size([16, 16, 16, 12])
        # 16 是 (5 + 分类3) * 形状2
        previous_upsampled_feature = None
        outputs = []
        for index, feature in enumerate(reversed(features_list)):
            if previous_upsampled_feature is not None:
                # 合并大的锚点距离抽取的特征到小的锚点距离抽取的特征
                feature = torch.cat((feature, previous_upsampled_feature), dim=1)
            # 计算用于合并的特征
            hidden = self.yolo_detectors[index][0](feature)
            # 放大特征 (用于下一次处理时合并)
            upsampled = self.yolo_detectors[index][1](hidden)
            # 计算最终的预测输出
            output = self.yolo_detectors[index][2](hidden)
            previous_upsampled_feature = upsampled
            outputs.append(output)
        # 连接所有输出
        # 注意顺序需要与 Anchors 一致
        outputs_flatten = []
        for output in reversed(outputs):
            output = output.permute(0, 2, 3, 1)
            output = output.reshape(output.shape[0], -1, MyModel.AnchorOutputs)
            outputs_flatten.append(output)
        outputs_all = torch.cat(outputs_flatten, dim=1)
        # 是否对象中心应该在 0 ~ 1 之间，使用 sigmoid 处理
        outputs_all[:,:,:1] = self.sigmoid(outputs_all[:,:,:1])
        # 分类应该在 0 ~ 1 之间，使用 sigmoid 处理
        outputs_all[:,:,5:] = self.sigmoid(outputs_all[:,:,5:])
        return outputs_all

    @staticmethod
    def loss_function(predicted, actual):
        """YOLO 使用的多任务损失计算器"""
        result_tensor, result_isobject_masks, result_nonobject_masks = actual
        objectness_losses = []
        offsets_losses = []
        labels_losses = []
        for x in range(result_tensor.shape[0]):
            mask_positive = result_isobject_masks[x]
            mask_negative = result_nonobject_masks[x]
            # 计算是否对象中心的损失，分别针对正负样本计算
            # 因为大部分区域不包含对象中心，这里减少负样本的损失对调整参数的影响
            objectness_loss_positive = nn.functional.mse_loss(
                predicted[x,mask_positive,0], result_tensor[x,mask_positive,0])
            objectness_loss_negative = nn.functional.mse_loss(
                predicted[x,mask_negative,0], result_tensor[x,mask_negative,0]) * 0.5
            objectness_losses.append(objectness_loss_positive)
            objectness_losses.append(objectness_loss_negative)
            # 计算区域偏移的损失，只针对正样本计算
            offsets_loss = nn.functional.mse_loss(
                predicted[x,mask_positive,1:5], result_tensor[x,mask_positive,1:5])
            offsets_losses.append(offsets_loss)
            # 计算标签分类的损失，分别针对正负样本计算
            labels_loss_positive = nn.functional.binary_cross_entropy(
                predicted[x,mask_positive,5:], result_tensor[x,mask_positive,5:])
            labels_loss_negative = nn.functional.binary_cross_entropy(
                predicted[x,mask_negative,5:], result_tensor[x,mask_negative,5:]) * 0.5
            labels_losses.append(labels_loss_positive)
            labels_losses.append(labels_loss_negative)
        loss = (
            torch.mean(torch.stack(objectness_losses)) +
            torch.mean(torch.stack(offsets_losses)) +
            torch.mean(torch.stack(labels_losses)))
        return loss

    @staticmethod
    def calc_accuracy(actual, predicted):
        """YOLO 使用的正确率计算器，这里只计算是否对象中心与标签分类的正确率，区域偏移不计算"""
        result_tensor, result_isobject_masks, result_nonobject_masks = actual
        # 计算是否对象中心的正确率，正样本和负样本的正确率分别计算再平均
        a = result_tensor[:,:,0]
        p = predicted[:,:,0] > MyModel.ObjScoreThreshold
        obj_acc_positive = ((a == 1) & (p == 1)).sum().item() / ((a == 1).sum().item() + 0.00001)
        obj_acc_negative = ((a == 0) & (p == 0)).sum().item() / ((a == 0).sum().item() + 0.00001)
        obj_acc = (obj_acc_positive + obj_acc_negative) / 2
        # 计算标签分类的正确率
        cls_total = 0
        cls_correct = 0
        for x in range(result_tensor.shape[0]):
            mask = list(sorted(result_isobject_masks[x] + result_nonobject_masks[x]))
            actual_classes = result_tensor[x,mask,5:].max(dim=1).indices
            predicted_classes = predicted[x,mask,5:].max(dim=1).indices
            cls_total += len(mask)
            cls_correct += (actual_classes == predicted_classes).sum().item()
        cls_acc = cls_correct / cls_total
        return obj_acc, cls_acc

    @staticmethod
    def convert_predicted_result(predicted):
        """转换预测结果到 (标签, 区域, 对象中心分数, 标签识别分数) 的列表，重叠区域使用 NMS 算法合并"""
        # 记录重叠的结果区域, 结果是 [ [(标签, 区域, RPN 分数, 标签识别分数)], ... ]
        final_result = []
        for anchor, tensor in zip(MyModel.Anchors, predicted):
            obj_score = tensor[0].item()
            if obj_score <= MyModel.ObjScoreThreshold:
                # 要求对象中心分数超过一定值
                continue
            offset = tensor[1:5].tolist()
            offset[0] = max(min(offset[0], 1), 0) # 中心点 x 的偏移应该在 0 ~ 1 之间
            offset[1] = max(min(offset[1], 1), 0) # 中心点 y 的偏移应该在 0 ~ 1 之间
            box = adjust_box_by_offset(anchor, offset)
            label_max = tensor[5:].max(dim=0)
            cls_score = label_max.values.item()
            label = label_max.indices.item()
            if label == 0:
                # 跳过非对象分类
                continue
            for index in range(len(final_result)):
                exists_results = final_result[index]
                if any(calc_iou(box, r[1]) > MyModel.IOUMergeThreshold for r in exists_results):
                    exists_results.append((label, box, obj_score, cls_score))
                    break
            else:
                final_result.append([(label, box, obj_score, cls_score)])
        # 合并重叠的结果区域 (使用 对象中心分数 * 标签识别分数 最高的区域为结果区域)
        for index in range(len(final_result)):
            exists_results = final_result[index]
            exists_results.sort(key=lambda r: r[2]*r[3])
            final_result[index] = exists_results[-1]
        return final_result

    @staticmethod
    def fix_predicted_result_from_history(cls_result, history_results):
        """根据历史结果减少预测结果中的误判，适用于视频识别，history_results 应为指定了 maxlen 的 deque"""
        # 要求历史结果中 50% 以上存在类似区域，并且选取历史结果中最多的分类
        history_results.append(cls_result)
        final_result = []
        if len(history_results) < history_results.maxlen:
            # 历史结果不足，不返回任何识别结果
            return final_result
        for label, box, rpn_score, cls_score in cls_result:
            # 查找历史中的近似区域
            similar_results = []
            for history_result in history_results:
                history_result = [(calc_iou(r[1], box), r) for r in history_result]
                history_result.sort(key = lambda r: r[0])
                if history_result and history_result[-1][0] > MyModel.IOUMergeThreshold:
                    similar_results.append(history_result[-1][1])
            # 判断近似区域数量是否过半
            if len(similar_results) < history_results.maxlen // 2:
                continue
            # 选取历史结果中最多的分类
            cls_groups = defaultdict(lambda: [])
            for r in similar_results:
                cls_groups[r[0]].append(r)
            most_common = sorted(cls_groups.values(), key=len)[-1]
            # 添加最多的分类中的最新的结果
            final_result.append(most_common[-1])
        return final_result

MyModel.Anchors = MyModel._generate_anchors()

def save_tensor(tensor, path):
    """保存 tensor 对象到文件"""
    torch.save(tensor, gzip.GzipFile(path, "wb"))

def load_tensor(path):
    """从文件读取 tensor 对象"""
    return torch.load(gzip.GzipFile(path, "rb"))

def calc_resize_parameters(sw, sh):
    """计算缩放图片的参数"""
    sw_new, sh_new = sw, sh
    dw, dh = IMAGE_SIZE
    pad_w, pad_h = 0, 0
    if sw / sh < dw / dh:
        sw_new = int(dw / dh * sh)
        pad_w = (sw_new - sw) // 2 # 填充左右
    else:
        sh_new = int(dh / dw * sw)
        pad_h = (sh_new - sh) // 2 # 填充上下
    return sw_new, sh_new, pad_w, pad_h

def resize_image(img):
    """缩放图片，比例不一致时填充"""
    sw, sh = img.size
    sw_new, sh_new, pad_w, pad_h = calc_resize_parameters(sw, sh)
    img_new = Image.new("RGB", (sw_new, sh_new))
    img_new.paste(img, (pad_w, pad_h))
    img_new = img_new.resize(IMAGE_SIZE)
    return img_new

def image_to_tensor(img):
    """转换图片对象到 tensor 对象"""
    arr = numpy.asarray(img)
    t = torch.from_numpy(arr)
    t = t.transpose(0, 2) # 转换维度 H,W,C 到 C,W,H
    t = t / 255.0 # 正规化数值使得范围在 0 ~ 1
    return t

def map_box_to_resized_image(box, sw, sh):
    """把原始区域转换到缩放后的图片对应的区域"""
    x, y, w, h = box
    sw_new, sh_new, pad_w, pad_h = calc_resize_parameters(sw, sh)
    scale = IMAGE_SIZE[0] / sw_new
    x = int((x + pad_w) * scale)
    y = int((y + pad_h) * scale)
    w = int(w * scale)
    h = int(h * scale)
    if x + w > IMAGE_SIZE[0] or y + h > IMAGE_SIZE[1] or w == 0 or h == 0:
        return 0, 0, 0, 0
    return x, y, w, h

def map_box_to_original_image(box, sw, sh):
    """把缩放后图片对应的区域转换到缩放前的原始区域"""
    x, y, w, h = box
    sw_new, sh_new, pad_w, pad_h = calc_resize_parameters(sw, sh)
    scale = IMAGE_SIZE[0] / sw_new
    x = int(x / scale - pad_w)
    y = int(y / scale - pad_h)
    w = int(w / scale)
    h = int(h / scale)
    if x + w > sw or y + h > sh or x < 0 or y < 0 or w == 0 or h == 0:
        return 0, 0, 0, 0
    return x, y, w, h

def calc_iou(rect1, rect2):
    """计算两个区域重叠部分 / 合并部分的比率 (intersection over union)"""
    x1, y1, w1, h1 = rect1
    x2, y2, w2, h2 = rect2
    xi = max(x1, x2)
    yi = max(y1, y2)
    wi = min(x1+w1, x2+w2) - xi
    hi = min(y1+h1, y2+h2) - yi
    if wi > 0 and hi > 0: # 有重叠部分
        area_overlap = wi*hi
        area_all = w1*h1 + w2*h2 - area_overlap
        iou = area_overlap / area_all
    else: # 没有重叠部分
        iou = 0
    return iou

def calc_box_offset(candidate_box, true_box):
    """计算候选区域与实际区域的偏移值，要求实际区域的中心点必须在候选区域中"""
    # 计算实际区域的中心点在候选区域中的位置，范围会在 0 ~ 1 之间
    x1, y1, w1, h1 = candidate_box
    x2, y2, w2, h2 = true_box
    x_offset = ((x2 + w2 // 2) - x1) / w1
    y_offset = ((y2 + h2 // 2) - y1) / h1
    # 计算实际区域长宽相对于候选区域长宽的比例，使用 log 减少过大的值
    w_offset = math.log(w2 / w1)
    h_offset = math.log(h2 / h1)
    return (x_offset, y_offset, w_offset, h_offset)

def adjust_box_by_offset(candidate_box, offset):
    """根据偏移值调整候选区域"""
    x1, y1, w1, h1 = candidate_box
    x_offset, y_offset, w_offset, h_offset = offset
    w2 = math.exp(w_offset) * w1
    h2 = math.exp(h_offset) * h1
    x2 = x1 + w1 * x_offset - w2 // 2
    y2 = y1 + h1 * y_offset - h2 // 2
    x2 = min(IMAGE_SIZE[0]-1,  x2)
    y2 = min(IMAGE_SIZE[1]-1,  y2)
    w2 = min(IMAGE_SIZE[0]-x2, w2)
    h2 = min(IMAGE_SIZE[1]-y2, h2)
    return (x2, y2, w2, h2)

def prepare_save_batch(batch, image_tensors, result_tensors, result_isobject_masks, result_nonobject_masks):
    """准备训练 - 保存单个批次的数据"""
    # 按索引值列表生成输入和输出 tensor 对象的函数
    def split_dataset(indices):
        indices_list = indices.tolist()
        image_tensors_splited = torch.stack([image_tensors[x] for x in indices_list])
        result_tensors_splited = torch.stack([result_tensors[x] for x in indices_list])
        result_isobject_masks_splited = [result_isobject_masks[x] for x in indices_list]
        result_nonobject_masks_splited = [result_nonobject_masks[x] for x in indices_list]
        return image_tensors_splited, (
            result_tensors_splited, result_isobject_masks_splited, result_nonobject_masks_splited)

    # 切分训练集 (80%)，验证集 (10%) 和测试集 (10%)
    random_indices = torch.randperm(len(image_tensors))
    training_indices = random_indices[:int(len(random_indices)*0.8)]
    validating_indices = random_indices[int(len(random_indices)*0.8):int(len(random_indices)*0.9):]
    testing_indices = random_indices[int(len(random_indices)*0.9):]
    training_set = split_dataset(training_indices)
    validating_set = split_dataset(validating_indices)
    testing_set = split_dataset(testing_indices)

    # 保存到硬盘
    save_tensor(training_set, f"data/training_set.{batch}.pt")
    save_tensor(validating_set, f"data/validating_set.{batch}.pt")
    save_tensor(testing_set, f"data/testing_set.{batch}.pt")
    print(f"batch {batch} saved")

def prepare():
    """准备训练"""
    # 数据集转换到 tensor 以后会保存在 data 文件夹下
    if not os.path.isdir("data"):
        os.makedirs("data")

    # 加载图片和图片对应的区域与分类列表
    # { (路径, 是否左右翻转): [ 区域与分类, 区域与分类, .. ] }
    # 同一张图片左右翻转可以生成一个新的数据，让数据量翻倍
    box_map = defaultdict(lambda: [])
    for filename in os.listdir(DATASET_1_IMAGE_DIR):
        # 从第一个数据集加载
        xml_path = os.path.join(DATASET_1_ANNOTATION_DIR, filename.split(".")[0] + ".xml")
        if not os.path.isfile(xml_path):
            continue
        tree = ET.ElementTree(file=xml_path)
        objects = tree.findall("object")
        path = os.path.join(DATASET_1_IMAGE_DIR, filename)
        for obj in objects:
            class_name = obj.find("name").text
            x1 = int(obj.find("bndbox/xmin").text)
            x2 = int(obj.find("bndbox/xmax").text)
            y1 = int(obj.find("bndbox/ymin").text)
            y2 = int(obj.find("bndbox/ymax").text)
            if class_name == "mask_weared_incorrect":
                # 佩戴口罩不正确的样本数量太少 (只有 123)，模型无法学习，这里全合并到戴口罩的样本
                class_name = "with_mask"
            box_map[(path, False)].append((x1, y1, x2-x1, y2-y1, CLASSES_MAPPING[class_name]))
            box_map[(path, True)].append((x1, y1, x2-x1, y2-y1, CLASSES_MAPPING[class_name]))
    df = pandas.read_csv(DATASET_2_BOX_CSV_PATH)
    for row in df.values:
        # 从第二个数据集加载，这个数据集只包含没有带口罩的图片
        filename, width, height, x1, y1, x2, y2 = row[:7]
        path = os.path.join(DATASET_2_IMAGE_DIR, filename)
        box_map[(path, False)].append((x1, y1, x2-x1, y2-y1, CLASSES_MAPPING["without_mask"]))
        box_map[(path, True)].append((x1, y1, x2-x1, y2-y1, CLASSES_MAPPING["without_mask"]))
    # 打乱数据集 (因为第二个数据集只有不戴口罩的图片)
    box_list = list(box_map.items())
    random.shuffle(box_list)
    print(f"found {len(box_list)} images")

    # 保存图片和图片对应的分类与区域列表
    batch_size = 20
    batch = 0
    image_tensors = [] # 图片列表
    result_tensors = [] # 图片对应的输出结果列表，包含 [ 是否对象中心, 区域偏移, 各个分类的可能性 ]
    result_isobject_masks = [] # 各个图片的包含对象的区域在 Anchors 中的索引
    result_nonobject_masks = [] # 各个图片不包含对象的区域在 Anchors 中的索引 (重叠率低于阈值的区域)
    for (image_path, flip), original_boxes_labels in box_list:
        with Image.open(image_path) as img_original: # 加载原始图片
            sw, sh = img_original.size # 原始图片大小
            if flip:
                img = resize_image(img_original.transpose(Image.FLIP_LEFT_RIGHT)) # 翻转然后缩放图片
            else:
                img = resize_image(img_original) # 缩放图片
            image_tensors.append(image_to_tensor(img)) # 添加图片到列表
        # 生成输出结果的 tensor
        result_tensor = torch.zeros((len(MyModel.Anchors), MyModel.AnchorOutputs), dtype=torch.float)
        result_tensor[:,5] = 1 # 默认分类为 other
        result_tensors.append(result_tensor)
        # 包含对象的区域在 Anchors 中的索引
        result_isobject_mask = []
        result_isobject_masks.append(result_isobject_mask)
        # 不包含对象的区域在 Anchors 中的索引
        result_nonobject_mask = []
        result_nonobject_masks.append(result_nonobject_mask)
        # 根据真实区域定位所属的锚点，然后设置输出结果
        negative_mapping = [1] * len(MyModel.Anchors)
        for box_label in original_boxes_labels:
            x, y, w, h, label = box_label
            if flip: # 翻转坐标
                x = sw - x - w
            x, y, w, h = map_box_to_resized_image((x, y, w, h), sw, sh) # 缩放实际区域
            if w < 20 or h < 20:
                continue # 缩放后区域过小
            # 检查计算是否有问题
            # child_img = img.copy().crop((x, y, x+w, y+h))
            # child_img.save(f"{os.path.basename(image_path)}_{x}_{y}_{w}_{h}_{label}.png")
            # 定位所属的锚点
            # 要求:
            # - 中心点落在锚点对应的区域中
            # - 重叠率超过一定值
            x_center = x + w // 2
            y_center = y + h // 2
            matched_anchors = []
            for index, anchor in enumerate(MyModel.Anchors):
                ax, ay, aw, ah = anchor
                is_center = (x_center >= ax and x_center < ax + aw and
                    y_center >= ay and y_center < ay + ah)
                iou = calc_iou(anchor, (x, y, w, h))
                if is_center and iou > IOU_POSITIVE_THRESHOLD:
                    matched_anchors.append((index, anchor)) # 区域包含对象中心并且重叠率超过一定值
                    negative_mapping[index] = 0
                elif iou > IOU_NEGATIVE_THRESHOLD:
                    negative_mapping[index] = 0 # 区域与某个对象重叠率超过一定值，不应该当作负样本
            for matched_index, matched_box in matched_anchors:
                # 计算区域偏移
                offset = calc_box_offset(matched_box, (x, y, w, h))
                # 修改输出结果的 tensor
                result_tensor[matched_index] = torch.tensor((
                    1, # 是否对象中心
                    *offset, # 区域偏移
                    *[int(c == label) for c in range(len(CLASSES))] # 对应分类
                ), dtype=torch.float)
                # 添加索引值
                # 注意如果两个对象同时定位到相同的锚点，那么只有一个对象可以被识别，这里后面的对象会覆盖前面的对象
                if matched_index not in result_isobject_mask:
                    result_isobject_mask.append(matched_index)
        # 没有找到可识别的对象时跳过图片
        if not result_isobject_mask:
            image_tensors.pop()
            result_tensors.pop()
            result_isobject_masks.pop()
            result_nonobject_masks.pop()
            continue
        # 添加不包含对象的区域在 Anchors 中的索引
        for index, value in enumerate(negative_mapping):
            if value:
                result_nonobject_mask.append(index)
        # 排序索引列表
        result_isobject_mask.sort()
        # 保存批次
        if len(image_tensors) >= batch_size:
            prepare_save_batch(batch, image_tensors, result_tensors,
                result_isobject_masks, result_nonobject_masks)
            image_tensors.clear()
            result_tensors.clear()
            result_isobject_masks.clear()
            result_nonobject_masks.clear()
            batch += 1
    # 保存剩余的批次
    if len(image_tensors) > 10:
        prepare_save_batch(batch, image_tensors, result_tensors,
            result_isobject_masks, result_nonobject_masks)

def train():
    """开始训练"""
    # 创建模型实例
    model = MyModel().to(device)

    # 创建多任务损失计算器
    loss_function = MyModel.loss_function

    # 创建参数调整器
    optimizer = torch.optim.Adam(model.parameters())

    # 记录训练集和验证集的正确率变化
    training_obj_accuracy_history = []
    training_cls_accuracy_history = []
    validating_obj_accuracy_history = []
    validating_cls_accuracy_history = []

    # 记录最高的验证集正确率
    validating_obj_accuracy_highest = -1
    validating_cls_accuracy_highest = -1
    validating_accuracy_highest = -1
    validating_accuracy_highest_epoch = 0

    # 读取批次的工具函数
    def read_batches(base_path):
        for batch in itertools.count():
            path = f"{base_path}.{batch}.pt"
            if not os.path.isfile(path):
                break
            x, (y, mask1, mask2) = load_tensor(path)
            yield x.to(device), (y.to(device), mask1, mask2)

    # 计算正确率的工具函数
    calc_accuracy = MyModel.calc_accuracy

    # 开始训练过程
    for epoch in range(1, 10000):
        print(f"epoch: {epoch}")

        # 根据训练集训练并修改参数
        # 切换模型到训练模式，将会启用自动微分，批次正规化 (BatchNorm) 与 Dropout
        model.train()
        training_obj_accuracy_list = []
        training_cls_accuracy_list = []
        for batch_index, batch in enumerate(read_batches("data/training_set")):
            # 划分输入和输出
            batch_x, batch_y = batch
            # 计算预测值
            predicted = model(batch_x)
            # 计算损失
            loss = loss_function(predicted, batch_y)
            # 从损失自动微分求导函数值
            loss.backward()
            # 使用参数调整器调整参数
            optimizer.step()
            # 清空导函数值
            optimizer.zero_grad()
            # 记录这一个批次的正确率，torch.no_grad 代表临时禁用自动微分功能
            with torch.no_grad():
                training_batch_obj_accuracy, training_batch_cls_accuracy = calc_accuracy(batch_y, predicted)
            # 输出批次正确率
            training_obj_accuracy_list.append(training_batch_obj_accuracy)
            training_cls_accuracy_list.append(training_batch_cls_accuracy)
            print(f"epoch: {epoch}, batch: {batch_index}: " +
                f"batch obj accuracy: {training_batch_obj_accuracy}, cls accuracy: {training_batch_cls_accuracy}")
        training_obj_accuracy = sum(training_obj_accuracy_list) / len(training_obj_accuracy_list)
        training_cls_accuracy = sum(training_cls_accuracy_list) / len(training_cls_accuracy_list)
        training_obj_accuracy_history.append(training_obj_accuracy)
        training_cls_accuracy_history.append(training_cls_accuracy)
        print(f"training obj accuracy: {training_obj_accuracy}, cls accuracy: {training_cls_accuracy}")

        # 检查验证集
        # 切换模型到验证模式，将会禁用自动微分，批次正规化 (BatchNorm) 与 Dropout
        model.eval()
        validating_obj_accuracy_list = []
        validating_cls_accuracy_list = []
        for batch in read_batches("data/validating_set"):
            batch_x, batch_y = batch
            predicted = model(batch_x)
            validating_batch_obj_accuracy, validating_batch_cls_accuracy = calc_accuracy(batch_y, predicted)
            validating_obj_accuracy_list.append(validating_batch_obj_accuracy)
            validating_cls_accuracy_list.append(validating_batch_cls_accuracy)
            # 释放 predicted 占用的显存避免显存不足的错误
            predicted = None
        validating_obj_accuracy = sum(validating_obj_accuracy_list) / len(validating_obj_accuracy_list)
        validating_cls_accuracy = sum(validating_cls_accuracy_list) / len(validating_cls_accuracy_list)
        validating_obj_accuracy_history.append(validating_obj_accuracy)
        validating_cls_accuracy_history.append(validating_cls_accuracy)
        print(f"validating obj accuracy: {validating_obj_accuracy}, cls accuracy: {validating_cls_accuracy}")

        # 记录最高的验证集正确率与当时的模型状态，判断是否在 20 次训练后仍然没有刷新记录
        validating_accuracy = validating_obj_accuracy * validating_cls_accuracy
        if validating_accuracy > validating_accuracy_highest:
            validating_obj_accuracy_highest = validating_obj_accuracy
            validating_cls_accuracy_highest = validating_cls_accuracy
            validating_accuracy_highest = validating_accuracy
            validating_accuracy_highest_epoch = epoch
            save_tensor(model.state_dict(), "model.pt")
            print("highest validating accuracy updated")
        elif epoch - validating_accuracy_highest_epoch > 20:
            # 在 20 次训练后仍然没有刷新记录，结束训练
            print("stop training because highest validating accuracy not updated in 20 epoches")
            break

    # 使用达到最高正确率时的模型状态
    print(f"highest obj validating accuracy: {validating_obj_accuracy_highest}",
        f"from epoch {validating_accuracy_highest_epoch}")
    print(f"highest cls validating accuracy: {validating_cls_accuracy_highest}",
        f"from epoch {validating_accuracy_highest_epoch}")
    model.load_state_dict(load_tensor("model.pt"))

    # 检查测试集
    testing_obj_accuracy_list = []
    testing_cls_accuracy_list = []
    for batch in read_batches("data/testing_set"):
        batch_x, batch_y = batch
        predicted = model(batch_x)
        testing_batch_obj_accuracy, testing_batch_cls_accuracy = calc_accuracy(batch_y, predicted)
        testing_obj_accuracy_list.append(testing_batch_obj_accuracy)
        testing_cls_accuracy_list.append(testing_batch_cls_accuracy)
    testing_obj_accuracy = sum(testing_obj_accuracy_list) / len(testing_obj_accuracy_list)
    testing_cls_accuracy = sum(testing_cls_accuracy_list) / len(testing_cls_accuracy_list)
    print(f"testing obj accuracy: {testing_obj_accuracy}, cls accuracy: {testing_cls_accuracy}")

    # 显示训练集和验证集的正确率变化
    pyplot.plot(training_obj_accuracy_history, label="training_obj_accuracy")
    pyplot.plot(training_cls_accuracy_history, label="training_cls_accuracy")
    pyplot.plot(validating_obj_accuracy_history, label="validating_obj_accuracy")
    pyplot.plot(validating_cls_accuracy_history, label="validating_cls_accuracy")
    pyplot.ylim(0, 1)
    pyplot.legend()
    pyplot.show()

def eval_model():
    """使用训练好的模型识别图片"""
    # 创建模型实例，加载训练好的状态，然后切换到验证模式
    model = MyModel().to(device)
    model.load_state_dict(load_tensor("model.pt"))
    model.eval()

    # 询问图片路径，并显示所有可能是人脸的区域
    while True:
        try:
            image_path = input("Image path: ")
            if not image_path:
                continue
            # 构建输入
            with Image.open(image_path) as img_original: # 加载原始图片
                sw, sh = img_original.size # 原始图片大小
                img = resize_image(img_original) # 缩放图片
                img_output = img_original.copy() # 复制图片，用于后面添加标记
                tensor_in = image_to_tensor(img)
            # 预测输出
            predicted = model(tensor_in.unsqueeze(0).to(device))[0]
            final_result = MyModel.convert_predicted_result(predicted)
            # 标记在图片上
            draw = ImageDraw.Draw(img_output)
            for label, box, obj_score, cls_score in final_result:
                x, y, w, h = map_box_to_original_image(box, sw, sh)
                score = obj_score * cls_score
                color = "#00FF00" if CLASSES[label] == "with_mask" else "#FF0000"
                draw.rectangle((x, y, x+w, y+h), outline=color)
                draw.text((x, y-10), CLASSES[label], fill=color)
                draw.text((x, y+h), f"{score:.2f}", fill=color)
                print((x, y, w, h), CLASSES[label], obj_score, cls_score)
            img_output.save("img_output.png")
            print("saved to img_output.png")
            print()
        except Exception as e:
            print("error:", e)

def eval_video():
    """使用训练好的模型识别视频"""
    # 创建模型实例，加载训练好的状态，然后切换到验证模式
    model = MyModel().to(device)
    model.load_state_dict(load_tensor("model.pt"))
    model.eval()

    # 询问视频路径，给可能是人脸的区域添加标记并保存新视频
    import cv2
    font = ImageFont.truetype("FreeMonoBold.ttf", 20)
    while True:
        try:
            video_path = input("Video path: ")
            if not video_path:
                continue
            # 读取输入视频
            video = cv2.VideoCapture(video_path)
            # 获取每秒的帧数
            fps = int(video.get(cv2.CAP_PROP_FPS))
            # 获取视频长宽
            size = (int(video.get(cv2.CAP_PROP_FRAME_WIDTH)), int(video.get(cv2.CAP_PROP_FRAME_HEIGHT)))
            # 创建输出视频
            video_output_path = os.path.join(
                os.path.dirname(video_path),
                os.path.splitext(os.path.basename(video_path))[0] + ".output.avi")
            result = cv2.VideoWriter(video_output_path, cv2.VideoWriter_fourcc(*"XVID"), fps, size)
            # 用于减少误判的历史结果
            history_results = deque(maxlen = fps // 2)
            # 逐帧处理
            count = 0
            while(True):
                ret, frame = video.read()
                if not ret:
                    break
                # opencv 使用的是 BGR, Pillow 使用的是 RGB, 需要转换通道顺序
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                # 构建输入
                img_original = Image.fromarray(frame_rgb) # 加载原始图片
                sw, sh = img_original.size # 原始图片大小
                img = resize_image(img_original) # 缩放图片
                img_output = img_original.copy() # 复制图片，用于后面添加标记
                tensor_in = image_to_tensor(img)
                # 预测输出
                predicted = model(tensor_in.unsqueeze(0).to(device))[0]
                cls_result = MyModel.convert_predicted_result(predicted)
                # 根据历史结果减少误判
                final_result = MyModel.fix_predicted_result_from_history(cls_result, history_results)
                # 标记在图片上
                draw = ImageDraw.Draw(img_output)
                for label, box, obj_score, cls_score in final_result:
                    x, y, w, h = map_box_to_original_image(box, sw, sh)
                    score = obj_score * cls_score
                    color = "#00FF00" if CLASSES[label] == "with_mask" else "#FF0000"
                    draw.rectangle((x, y, x+w, y+h), outline=color, width=3)
                    draw.text((x, y-20), CLASSES[label], fill=color, font=font)
                    draw.text((x, y+h), f"{score:.2f}", fill=color, font=font)
                # 写入帧到输出视频
                frame_rgb_annotated = numpy.asarray(img_output)
                frame_bgr_annotated = cv2.cvtColor(frame_rgb_annotated, cv2.COLOR_RGB2BGR)
                result.write(frame_bgr_annotated)
                count += 1
                if count % fps == 0:
                    print(f"handled {count//fps}s")
            video.release()
            result.release()
            cv2.destroyAllWindows()
            print(f"saved to {video_output_path}")
            print()
        except Exception as e:
            raise
            print("error:", e)

def main():
    """主函数"""
    if len(sys.argv) < 2:
        print(f"Please run: {sys.argv[0]} prepare|train|eval")
        exit()

    # 给随机数生成器分配一个初始值，使得每次运行都可以生成相同的随机数
    # 这是为了让过程可重现，你也可以选择不这样做
    random.seed(0)
    torch.random.manual_seed(0)

    # 根据命令行参数选择操作
    operation = sys.argv[1]
    if operation == "prepare":
        prepare()
    elif operation == "train":
        train()
    elif operation == "eval":
        eval_model()
    elif operation == "eval-video":
        eval_video()
    else:
        raise ValueError(f"Unsupported operation: {operation}")

if __name__ == "__main__":
    main()
```

预处理数据集并且执行训练的命令：

``` text
python3 example.py prepare
python3 example.py train
```

训练结果：

``` text
epoch: 42, batch: 555: batch obj accuracy: 0.9909388836542586, cls accuracy: 0.983006698089804
epoch: 42, batch: 556: batch obj accuracy: 0.9814650010596331, cls accuracy: 0.9774137503102507
epoch: 42, batch: 557: batch obj accuracy: 0.9878546962973783, cls accuracy: 0.9791485664639444
epoch: 42, batch: 558: batch obj accuracy: 0.9804549878809472, cls accuracy: 0.9869710882243454
epoch: 42, batch: 559: batch obj accuracy: 0.9874521037216837, cls accuracy: 0.9825083736509118
epoch: 42, batch: 560: batch obj accuracy: 0.9686452380905726, cls accuracy: 0.9792752544055597
epoch: 42, batch: 561: batch obj accuracy: 0.9850456887221628, cls accuracy: 0.981502172563625
epoch: 42, batch: 562: batch obj accuracy: 0.9667773027084426, cls accuracy: 0.979282967373775
epoch: 42, batch: 563: batch obj accuracy: 0.9744239536970148, cls accuracy: 0.9843711237906226
training obj accuracy: 0.9823339177948931, cls accuracy: 0.9797140932720472
validating obj accuracy: 0.9166056052234632, cls accuracy: 0.9772082398493264
stop training because highest validating accuracy not updated in 20 epoches
highest obj validating accuracy: 0.94078897076641 from epoch 21
highest cls validating accuracy: 0.9635325289895568 from epoch 21
testing obj accuracy: 0.9438541768431002, cls accuracy: 0.9637055484080282
```

看起来正确率不错，但因为 YOLO 只有单步，实际上对是否包含对象的误判率比 Faster-RCNN 要高一些🙁。

使用训练好的模型识别图片的命令，输入图片路径并回车即可生成标记过的图片：

``` text
python3 example.py eval
```

使用训练好的模型识别视频的命令，输入视频路径并回车即可生成标记过的视频：

``` text
python3 example.py eval-video
```

标记后的例子如下，能用，但和前一篇相比效果差一点🤒。

![](wuhan.output.gif)

![](shanghai.output.gif)

## 写在最后

妈蛋，写了好几篇识别人脸位置的文章，这篇是最后一篇了。下一篇将会介绍根据人脸找出是哪一个人的模型，可以用来实现打卡，也可以用来抓逃犯😡。

最后祝大家牛年加工资，中国股市牛年牛逼🐮重回 6000 点。