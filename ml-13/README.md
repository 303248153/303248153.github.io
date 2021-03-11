# 写给程序员的机器学习入门 (十三) - 人脸识别

博客园终于整改完了啊😩，以后应该能看到比较干净的评论了，给博客园团队点个赞。

这篇将会介绍人脸识别模型的实现，以及如何结合前几篇文章的模型来识别图片上的人，最终效果如下：

![img_output4.png](./img_output4.png)

这话我举双手双脚同意🤬，美国是在太霸道了，中国绝不能在领土和主权问题上退让。

## 实现人脸识别的方法

你可能会想起[第八篇文章](https://www.cnblogs.com/zkweb/p/13354826.html)介绍如何识别图片上物体类型的 CNN 模型，那么人脸是否也能用同样的方法识别呢？例如有 100 个人，把这 100 个人当作 100 个分类，然后用他们的照片来训练，似乎就可以训练出可以根据图片识别哪个人的模型了，真的吗🤔。

![cifar-10.png](cifar-10.png)

很遗憾，用于识别物体类型的模型并不能用在人脸识别上，主要有以下原因：

- 识别物体类型的模型通常要求每个分类有大量的图片，而人脸识别模型很多时候只能拿到个位数的人脸，这样训练出来的精度很不理想。这个问题又称 One-shot 学习问题 (每个分类只有很少的样本数量)。
- 识别物体类型的模型只能识别训练过的类型，如果想添加新类型则需要重新开始训练 (如果一开始预留有多的分类数量可以基于上一次的模型状态继续训练，这个做法又称迁移学习)
- 同上，识别物体类型的模型不能识别没有学习过的人物

我们需要用不同的方法来实现人脸识别😤，目前主流的方法有两种，一种是基于指标，根据人脸生成对应的编码，然后调整编码之间的距离 (同一个人的编码接近，不同的人的编码远离) 来实现人脸的区分；另一种是基于分类，可以看作是识别物体类型的模型的改进版，同样会根据人脸生成对应的编码，但最后会添加一层输出分类的线性模型，来实现间接的调整编码。

### 基于指标的方法

基于指标的方法使用的模型结构如下：

![01](./01.png)

我们最终想要模型根据人脸输出编码，如果是同一个人那么编码就会比较接近，如果是不同的人那么编码就会比较远离。如果训练成功，我们可以根据已有的人脸构建一个编码数据库，识别新的人脸时生成新的人脸的编码，然后对比数据库中的编码找出最接近的人脸，如下图所示。

![02](./02.png)

输出编码的模型定义如下，这里的编码长度是 32 (完整代码会在后面给出)：

``` python
# Resnet 的实现
self.resnet = torchvision.models.resnet18(num_classes=256)
# 支持黑白图片
if USE_GRAYSCALE:
    self.resnet.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
# 最终输出编码的线性模型
# 因为 torchvision 的 resnet 最终会使用一个 Linear，这里省略掉第一个 Linear
self.encode_model = nn.Sequential(
    nn.ReLU(inplace=True),
    nn.Linear(256, 128),
    nn.ReLU(inplace=True),
    nn.Linear(128, 32))
```

而比较编码找出最接近的人脸可以使用以下的代码 (计算编码中各个值的相差的平方的合计)：

``` python
diff = (new_code - exists_code).pow(2).sum(dim=1).sort()
most_similar = diff.indices[0]
```

如果编码数据库中有大量的编码，计算所有编码的距离消耗会比较大，我们可以使用支持搜索向量的数据库，例如把编码保存到  Elastic Search 数据库并使用 dense_vector 类型，Elastic Search 数据库会根据编码构建索引并实现更高效的查找🤒。

看到这里你可能会觉得，就这么点吗？那该如何训练模型，让同一个人的编码更接近呢？这就是最难的部分了🤕，一开始大家想到的是以下的方式：

``` python
# 计算损失的逻辑
loss1 = 同一个人的编码距离
loss2 = ReLU(常量A - 不同的人的编码距离)
loss = loss1 + loss2
```

这样做看上去经过训练以后同一个人的编码会完全相同，而不同的人的编码距离最少需要大于常量A，但实际上这个方式很难训练成功，因为即使是同一个人，图片上的人脸角度、光线、脸色、以及背景都不一样，生成完全一样的编码会非常困难。

2015 年的 [Facenet 论文](https://arxiv.org/abs/1503.03832) 提出了使用 Triplet Loss 来训练人脸识别模型的手法，简单来说就是同时准备两个人的三张图片 (又称三元组)，然后让同一个人的编码距离小于不同的人的编码距离，计算方式如下：

``` python
loss = ReLU(同一个人的编码距离 + 常量A - 不同的人的编码距离)
```

看上去只是把前面的 loss1 放到了 loss2 的 ReLU 函数里面啊，对🤒，这么做了以后同一个人的编码距离不需要等于 0，只需要和不同的人的编码距离相差常量A即可，如下图所示：

![03](./03.png)

经过训练以后的编码分布大概会像下图，同一个人物的编码不会完全一样但会聚集在一起 （这就是一种通过机器学习实现聚类的方法🤒)：

![04](./04.png)

现在我们知道选取两个人的三张图片 (又称三元组)，然后使用 Triplet Loss 计算损失即可训练模型聚类人脸，那应该怎样选取图片呢？简单的做法是随机选取图片，但随着训练次数增多，同一个人物的编码距离小于不同人物的编码距离的频率就越高，也即是说 loss 为 0 的频率越高，如果 90% 的 loss 为 0，那么就代表 90% 的计算都白费了。而且，这样训练出来的模型对于看上去相似但是不是同一个人的识别能力会比较弱。

更好的方法是记录上一次训练时各个图片的编码，先选取一张基础图片 (Anchor)，然后选取"同一个人物但编码距离最远"的一张图片 (Hard Positive)，和"不同的人但编码距离最近"的一张图片 (Hard Negative)。这样可以给模型尽可能大的压力来训练看上去不相似但是同一个人，和看上去相似但不是同一个人的识别能力。这个方法实现起来有一定的难度，因为：

- 如果训练的图片数量很多，例如上百万张，那么每次选取图片都需要计算基础图片的编码和上百万个编码之间的距离，计算量会非常庞大，训练起来像乌龟一样慢😱
- 如果你不小心把同一个人的图片放到其他人的文件夹，或者混杂一些质量比较垃圾的图片，这时候就好玩了，模型会想方设法的去适应这些图片，导致训练出来的模型不能泛化
- 如果你一直给模型看很相似的人物然后告诉模型这不是同一个人 (有可能因为第二个原因，也有可能因为真是双胞胎🤗)，那模型下次看到同一个人也会怀疑不是同一个，同样会影响模型的泛化能力

Facenet 中缓解这个问题的方法是把图片切分小批次 (Mini batch)，然后在小批次中局部查找编码距离最近但不同的人，也会在小部分样本中随机选取批次外的人物。本文给出的实现将会使用另一种方法，具体看后面的介绍吧🥳。

顺道一提，Facenet 中使用的编码长度是 32，常量A的值是 0.2，本文的实现也会使用相同的参数，参考后面给出的代码叭。

### 基于分类的方法

基于指标的方法可以直接调整编码之间的距离，但选取三元组有一定的难度，并且随着数据量增多，选取时的计算量也会越多。基于分类的方法是另外一种途径，可以无须选取三元组而间接的调整编码之间的距离。模型的结构如下：

![05](./05.png)

看起来只是在输出编码以后加一个单层线性模型，然后输出人物对应的分类，如果是同一个分类那么编码应该会更接近。如果忽视掉编码，把多层线性模型和单层线性连在一起，就是普通识别物体类型的模型。真的能行吗？

当然，没这么简单🤬，如文章开始提到过的，直接应用识别物体类型的模型到人脸上效果会很差，因为各个人的样本数量都不多，加上最后的单层线性模型只需要划分编码到分类而不需要聚集编码，训练出来的模型识别能力会很弱。训练出来的人脸分布可能会像下图一样：

![06](./06.png)

关键点在于计算损失的函数，普通识别物体类型的模型会使用 Softmax + CrossEntropyLoss，而识别人脸的模型则需要使用变种函数计算损失，本文不会详细介绍这些变种函数，如果你有兴趣可以参考 [CosFace](https://arxiv.org/abs/1801.09414)，[SphereFace](https://arxiv.org/abs/1704.08063v4)，和 [ArcFace](https://arxiv.org/abs/1801.07698v2) 的论文。

因为基于分类的方法速度更快，它更适合计算数量非常庞大的数据集，而这篇的例子收集到的人脸数据比较少，所有还是会采用基于指标的方法来实现，慢一点就慢一点吧🤒。

### 关于计算编码距离的补充

计算编码距离主要有两种方法，第一种是计算欧几里德距离 (Euclidean Distance)，也就是在前面看到过的计算方法；第二种是计算余弦相似度 (Cosine Similarity)，如果你参考基于分类的方法的论文会发现里面基本上都会使用余弦相似度计算。

使用 pytorch 计算欧几里德距离的例子如下，Triplet Loss 使用的时候会除掉 sqrt 的部分：

``` python
>>> import torch
>>> a = torch.tensor([1, 0, 0, 0.9, 0.1])
>>> b = torch.tensor([1, 0, 0.2, 0.8, 0])
>>> (a - b).pow(2).sum().sqrt()
tensor(0.2449)
// 结果等于 0 代表完全相同
```

使用 pytorch 计算余弦相似度的例子如下：

``` python
>>> import torch
>>> a = torch.tensor([1, 0, 0, 0.9, 0.1])
>>> b = torch.tensor([1, 0, 0.2, 0.8, 0])
>>> torch.nn.functional.cosine_similarity(a, b, dim=0)
tensor(0.9836)
// 相当于
>>> (a * b).sum() / (a.pow(2).sum().sqrt() * b.pow(2).sum().sqrt())
tensor(0.9836)
// 结果等于 1 代表完全相同，结果等于 0 代表完全相反
```

## 实现人脸认证的方法

使用以上的方法我们可以找到最接近的人脸，那这个人脸是否就是我们传入的人脸是同一个人呢？判断是否同一个人的依据可以是编码距离是否小于某个阈值，然而这个阈值是很难定义的。有个现象是，经过训练的同一个人的编码距离明显小于没有经过训练的同一个人的编码距离，人脸分布可能会如下：

![07](./07.png)

一个比较好的方法是训练另外一个专门根据人脸编码距离判断是否同一个人的模型，这个模型只有一层线性模型，它会给编码中的每个指标乘以一个系数，然后加上偏移值，再交给 Sigmoid 转换到 0 ～ 1 之间的值，0 代表不是同一个人，1 代表是同一个人。

模型的定义如下，完整代码参考后面：

``` python
self.verify_model = nn.Sequential(
    nn.Linear(32, 1),
    nn.Sigmoid())
```

假设如果有以下的编码：

``` python
>>> a = torch.tensor([1, 0, 0, 0.9, 0.1])
>>> b = torch.tensor([1, 0, 0.2, 0.8, 0])
>>> c = torch.tensor([1, 1, 0.9, 0.2, 1])
```

a 与 b，a 与 c 之间的距离可以用以下方式计算：

``` python
>>> diff_1 = (a - b).pow(2)
>>> diff_1
tensor([0.0000, 0.0000, 0.0400, 0.0100, 0.0100])
>>> diff_2 = (a - c).pow(2)
>>> diff_2
tensor([0.0000, 1.0000, 0.8100, 0.4900, 0.8100])
```

再假设模型参数如下：

``` python
>>> w = torch.tensor([[-1.58, -2.96, -0.8, -0.1, -1.28]]).transpose(0, 1)
>>> b = torch.tensor(3.68)
```

再应用到编码相差值就会发现 a 与 b 是同一个人的可能性很高 (接近 1)，而 a 与 c 是同一个人的可能性很低 (接近 0)：

``` python
>>> torch.nn.functional.sigmoid(diff_1.unsqueeze(0).mm(w) + b)
tensor([[0.9743]])
>>> torch.nn.functional.sigmoid(diff_2.unsqueeze(0).mm(w) + b)
tensor([[0.2662]])
```

训练人脸认证模型的代码会在后面给出。

看到这里你可能会问，为什么需要给编码中的指标分别训练不同的系数呢？不能直接用 sum 相加起来，再根据这个相加的值来判断吗？想想编码里面的内容代表了什么，模型为了区分人脸，需要给不同的人物分配不同的编码，而这个编码实际上就隐含了人物的属性，例如某个指标可能代表人物的性别，某个指标可能代表人物的年龄，某个指标可能代表人物的器官形状，这些指标的相差值有的会更重要，例如代表性别的指标不一致那就肯定是不同的人了，而代表年龄的指标不一致则还有余地。给每个指标分别训练不同的系数 (也可以称为权重) 可以更精准的判断是否同一个人。

## 准备训练使用的数据集

好了，又到动手的时候了🤗。首先我们需要准备数据集，这次还是在 kaggle 上扒，一共有三个数据集符合要求，地址如下：

- https://www.kaggle.com/atulanandjha/lfwpeople
- https://www.kaggle.com/vasukipatel/face-recognition-dataset
- https://www.kaggle.com/hereisburak/pins-face-recognition

合计一共有 5855 个人和 33329 张图片，和其他公用数据集一样，里面大部分是白人，对亚洲人和黑人的效果会打个折🤒。训练人脸识别模型通常需要上百万张人脸，而这里只有三万多张，所以预计精确度会稍微低一些🤕。

需要注意的是，里面有相当一部分人物是只有一张图片的，这种人物会只拿来当负样本 (不同的人物) 使用。

此外，训练人脸识别模型的时候人脸的位置和占比要比较标准，数据质量会直接影响训练出来的正确率。以上三个数据集的人脸图片都是经过预处理的，不需要使用上一篇文章介绍的模型来调整中心点，但数据集的人脸占比不一样，所以会经过裁剪再参与训练。

![08](./08.png)

裁剪比例分别是：

- 第一个数据集：中心 50%
- 第二个数据集：不裁剪
- 第三个数据集：中心 70%

## 完整代码

到介绍完整代码的时候了😭，以下代码包含了人脸识别模型和人脸认证模型，需要先训练人脸识别模型，再训练人脸认证模型，代码下面会给出一些实现细节的说明。

``` python
import os
import sys
import torch
import gzip
import itertools
import random
import numpy
import math
import json
import torchvision
from PIL import Image
from torch import nn
from matplotlib import pyplot
from collections import defaultdict
from functools import lru_cache

# 缩放图片的大小
IMAGE_SIZE = (80, 80)
# 训练使用的数据集路径
DATASET_1_DIR = "./dataset/lfwpeople/lfw_funneled"
DATASET_2_DIR = "./dataset/face-recognition-dataset/Faces/Faces"
DATASET_3_DIR = "./dataset/105_classes_pins_dataset"
# 每一轮训练中样本的重复次数
REPEAT_SAMPLES = 2
# 用于对比的不同人物 (负样本) 数量
NEGATIVE_SAMPLES = 10
# 负样本中随机抽取的数量
NEGATIVE_RANDOM_SAMPLES = 3
# 跳过最接近的人脸数量
# 避免双胞胎问题：
# 如果你给模型大量很相似的人脸 (有可能因为误标记，有可能因为图片质量很低，也有可能因为真相似)
# 然后跟模型说不是同一个人，下次模型看到未经过训练的同一个人也会认为不是
# Facenet 论文中避免这个问题使用的方法是计算局部最接近的不同人物
# 而这里会计算全局最接近但跳过排在前面的人脸，数据量不多的时候可以这么做
NEGATIVE_SKIP_NEAREST = 20
# 识别同一人物最少要求的图片数量
MINIMAL_POSITIVE_SAMPLES = 2
# 处理图片前是否先转换为黑白图片
USE_GRAYSCALE = True

# 用于启用 GPU 支持
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class FaceRecognitionModel(nn.Module):
    """人脸识别模型，计算用于寻找最接近人脸的编码 (基于 ResNet 的变种)"""
    # 编码长度
    EmbeddedSize = 32
    # 要求不同人物编码之间的距离 (平方值合计)
    ExclusiveMargin = 0.2

    def __init__(self):
        super().__init__()
        # Resnet 的实现
        self.resnet = torchvision.models.resnet18(num_classes=256)
        # 支持黑白图片
        if USE_GRAYSCALE:
            self.resnet.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
        # 最终输出编码的线性模型
        # 因为 torchvision 的 resnet 最终会使用一个 Linear，这里省略掉第一个 Linear
        self.encode_model = nn.Sequential(
            nn.ReLU(inplace=True),
            nn.Linear(256, 128),
            nn.ReLU(inplace=True),
            nn.Linear(128, FaceRecognitionModel.EmbeddedSize))

    def forward(self, x):
        tmp = self.resnet(x)
        y = self.encode_model(tmp)
        return y

    @staticmethod
    def loss_function(predicted):
        """损失计算器"""
        losses = []
        verify_positive = torch.ones(1).to(device)
        verify_negative = torch.zeros(NEGATIVE_SAMPLES).to(device)
        for index in range(0, predicted.shape[0], 2 + NEGATIVE_SAMPLES):
            a = predicted[index]   # 基础人物的编码
            b = predicted[index+1] # 基础人物的编码 (另一张图片)
            c = predicted[index+2:index+2+NEGATIVE_SAMPLES] # 对比人物的编码
            # 计算编码相差值
            diff_positive = (a - b).pow(2).sum()
            diff_negative = (a - c).pow(2).sum(dim=1)
            # 计算损失
            # 使用 Triplet Loss，要求同一人物编码距离和不同人物编码距离至少相差 ExclusiveMargin
            loss = nn.functional.relu(
                diff_positive - diff_negative + FaceRecognitionModel.ExclusiveMargin).sum()
            losses.append(loss)
        loss_total = torch.stack(losses).mean()
        return loss_total

    @staticmethod
    def calc_accuracy(predicted):
        """正确率计算器"""
        total_count = 0
        correct_count = 0
        for index in range(0, predicted.shape[0], 2 + NEGATIVE_SAMPLES):
            a = predicted[index]   # 基础人物的编码
            b = predicted[index+1] # 基础人物的编码 (另一张图片)
            c = predicted[index+2:index+2+NEGATIVE_SAMPLES] # 对比人物的编码
            # 判断同一人物的编码是否小于不同人物的编码
            diff_positive = (a - b).pow(2).sum()
            diff_negative = (a - c).pow(2).sum(dim=1)
            if (diff_positive < diff_negative).sum() == diff_negative.shape[0]:
                correct_count += 1
            total_count += 1
        return correct_count / total_count

class FaceVerificationModel(nn.Module):
    """人脸认证模型，判断是否同一个人，参数是编码相差值的平方"""
    # 判断是否同一个人的阈值，实际使用模型时可以用更高的值防止误判
    VerifyThreshold = 0.5

    def __init__(self):
        super().__init__()
        # 判断是否同一人物的线性模型
        self.verify_model = nn.Sequential(
            nn.Linear(FaceRecognitionModel.EmbeddedSize, 1),
            nn.Sigmoid())

    def forward(self, x):
        # 经过训练后 weight 应该是负数，bias 应该是正数
        y = self.verify_model(x)
        return y.view(-1)

    @staticmethod
    def loss_function(predicted):
        """损失计算器"""
        # 输出应该为 [ 同一人物, 不同人物, 不同人物, ..., 同一人物, 不同人物, 不同人物, ... ]
        # 这里需要分别计算正负损失，否则会因为负样本占多而引起 bias 被调整为负数
        positive_indexes = []
        negative_indexes = []
        for index in list(range(0, predicted.shape[0], 1+NEGATIVE_SAMPLES)):
            positive_indexes.append(index)
            negative_indexes += list(range(index+1, index+1+NEGATIVE_SAMPLES))
        positive_loss = nn.functional.mse_loss(
            predicted[positive_indexes], torch.ones(len(positive_indexes)).to(device))
        negative_loss = nn.functional.mse_loss(
            predicted[negative_indexes], torch.zeros(len(negative_indexes)).to(device))
        return (positive_loss + negative_loss) / 2

    @staticmethod
    def calc_accuracy(predicted):
        """正确率计算器"""
        positive_correct = 0
        positive_total = 0
        negative_correct = 0
        negative_total = 0
        for index in range(0, predicted.shape[0], 1+NEGATIVE_SAMPLES):
            positive_correct += (predicted[index] >=
                FaceVerificationModel.VerifyThreshold).sum().item()
            negative_correct += (predicted[index+1:index+1+NEGATIVE_SAMPLES] <
                FaceVerificationModel.VerifyThreshold).sum().item()
            positive_total += 1
            negative_total += NEGATIVE_SAMPLES
        # 因为负样本占大多数，这里返回正样本正确率和负样本正确率的平均值
        return (positive_correct / positive_total + negative_correct / negative_total) / 2

def save_tensor(tensor, path):
    """保存 tensor 对象到文件"""
    torch.save(tensor, gzip.GzipFile(path, "wb"))

# 为了减少读取时间这里缓存了读取的 tensor 对象
# 如果内存不够应该适当减少 maxsize
@lru_cache(maxsize=10000)
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

def image_to_tensor_grayscale(img):
    """缩放并转换图片对象到 tensor 对象 (黑白)"""
    img = img.convert("L") # 转换到黑白图片并缩放
    arr = numpy.asarray(img)
    t = torch.from_numpy(arr)
    t = t.unsqueeze(0) # 添加通道
    t = t / 255.0 # 正规化数值使得范围在 0 ~ 1
    return t

def image_to_tensor_rgb(img):
    """缩放并转换图片对象到 tensor 对象 (彩色)"""
    img = img.convert("RGB") # 缩放图片
    arr = numpy.asarray(img)
    t = torch.from_numpy(arr)
    t = t.transpose(0, 2) # 转换维度 H,W,C 到 C,W,H
    t = t / 255.0 # 正规化数值使得范围在 0 ~ 1
    return t

if USE_GRAYSCALE:
    image_to_tensor = image_to_tensor_grayscale
else:
    image_to_tensor = image_to_tensor_rgb

def prepare():
    """准备训练"""
    # 数据集转换到 tensor 以后会保存在 data 文件夹下
    if not os.path.isdir("data"):
        os.makedirs("data")

    # 截取后的人脸图片会保存在 debug_faces 文件夹下
    if not os.path.isdir("debug_faces"):
        os.makedirs("debug_faces")

    # 查找人物和对应的图片路径列表
    # { 人物名称: [ 图片路径, 图片路径, .. ] }
    images_map = defaultdict(lambda: [])
    def add_image(name, path):
        if os.path.splitext(path)[1].lower() not in (".jpg", ".png"):
            return
        name = name.replace(" ", "").replace("-", "").replace(".", "").replace("_", "").lower()
        images_map[name].append(path)
    for dirname in os.listdir(DATASET_1_DIR):
        dirpath = os.path.join(DATASET_1_DIR, dirname)
        if not os.path.isdir(dirpath):
            continue
        for filename in os.listdir(dirpath):
            add_image(dirname, os.path.join(DATASET_1_DIR, dirname, filename))
    for filename in os.listdir(DATASET_2_DIR):
        add_image(filename.split("_")[0], os.path.join(DATASET_2_DIR, filename))
    for dirname in os.listdir(DATASET_3_DIR):
        dirpath = os.path.join(DATASET_3_DIR, dirname)
        name = dirname.replace("pins_", "")
        if not os.path.isdir(dirpath):
            continue
        for filename in os.listdir(dirpath):
            add_image(name, os.path.join(DATASET_3_DIR, dirname, filename))
    images_count = sum(map(len, images_map.values()))
    print(f"found {len(images_map)} peoples and {images_count} images")

    # 保存各个人物的图片数据
    # 这里不翻转图片，因为人脸照片通常不会左右翻转，而且部分器官的特征会因左右有差异
    img_index = 0
    for index, (name, paths) in enumerate(images_map.items()):
        images = []
        for path in paths:
            img = Image.open(path)
            # 裁剪图片让各个数据集的人脸占比更接近
            if path.startswith(DATASET_1_DIR):
                w, h = img.size
                img = img.crop((int(w*0.25), int(h*0.25), int(w*0.75), int(h*0.75)))
            elif path.startswith(DATASET_3_DIR):
                w, h = img.size
                img = img.crop((int(w*0.15), int(h*0.15), int(w*0.85), int(h*0.85)))
            # 保存截取后的人脸图片以调试范围
            img.save(f"debug_faces/{img_index}.png")
            img_index += 1
            images.append(img)
        tensors = [ image_to_tensor(resize_image(img)) for img in images ]
        tensor = torch.stack(tensors) # 维度: (图片数量, 3, 宽度, 高度)
        save_tensor(tensor, os.path.join("data", f"{name}.{len(images)}.pt"))
        print(f"saved {index+1}/{len(images_map)} peoples")

    print("done")

def train():
    """开始训练人脸识别模型"""
    # 创建模型实例
    model = FaceRecognitionModel().to(device)

    # 创建损失计算器
    loss_function = model.loss_function

    # 创建参数调整器
    optimizer = torch.optim.Adam(model.parameters())

    # 记录训练集和验证集的正确率变化
    training_accuracy_history = []
    validating_accuracy_history = []

    # 记录最高的验证集正确率
    validating_accuracy_highest = -1
    validating_accuracy_highest_epoch = 0

    # 计算正确率的工具函数
    calc_accuracy = model.calc_accuracy

    # 读取人物列表，区分图片数量足够的人物和图片数量不足的人物
    # 图片数量不足的人物会作为负样本使用
    filenames = os.listdir("data")
    multiple_samples = []
    single_samples = []
    for filename in filenames:
        if int(filename.split('.')[-2]) >= MINIMAL_POSITIVE_SAMPLES:
            multiple_samples.append(filename)
        else:
            single_samples.append(filename)
    random.shuffle(multiple_samples)
    random.shuffle(single_samples)
    total_multiple_samples = len(multiple_samples)
    total_single_samples = len(single_samples)

    # 分割训练集 (80%)，验证集 (10%) 和测试集 (10%)
    training_set = multiple_samples[:int(total_multiple_samples*0.8)]
    training_set_single = single_samples[:int(total_single_samples*0.8)]
    validating_set = multiple_samples[int(total_multiple_samples*0.8):int(total_multiple_samples*0.9)]
    validating_set_single = single_samples[int(total_single_samples*0.8):int(total_single_samples*0.9)]
    testing_set = multiple_samples[int(total_multiple_samples*0.9):]
    testing_set_single = single_samples[int(total_single_samples*0.9):]

    # 训练集的各个人物对应的编码 (基于最后以后一次训练使用的图片)
    training_image_to_vector_index = {}
    training_vector_index_to_image = {}
    for filename in training_set + training_set_single:
        for image_index in range(int(filename.split('.')[1])):
            vector_index = len(training_image_to_vector_index)
            training_image_to_vector_index[(filename, image_index)] = vector_index
            training_vector_index_to_image[vector_index] = (filename, image_index)
    training_vectors = torch.zeros(len(training_image_to_vector_index), FaceRecognitionModel.EmbeddedSize)
    training_vectors_calculated_indices = set()

    # 生成用于训练的输入
    # 返回 [ 基础图片, 同一人物图片 (正样本), 不同人物图片 (负样本), ... ]
    def generate_inputs(dataset_multiple, dataset_single, batch_size):
        # 获取已计算过的编码
        is_training = dataset_multiple == training_set
        if is_training:
            calculated_index_list = list(training_vectors_calculated_indices)
            calculated_index_set = set(calculated_index_list)
            calculated_index_to_image = {
                ci: training_vector_index_to_image[vi]
                for ci, vi in enumerate(calculated_index_list)
            }
            training_vectors_calculated = training_vectors[calculated_index_list]
        # 枚举数据集，会重复 REPEAT_SAMPLES 次以减少随机选择导致的正确率浮动
        image_tensors = []
        vector_indices = []
        for base_filename in dataset_multiple * REPEAT_SAMPLES:
            # 读取基础人物的图片
            base_tensor = load_tensor(os.path.join("data", base_filename))
            base_tensors = list(enumerate(base_tensor))
            # 打乱顺序，然后两张两张图片的选取基础图片和正样本
            random.shuffle(base_tensors)
            for index in range(0, len(base_tensors)-1, 2):
                # 添加基础图片和正样本到列表
                anchor_image_index, anchor_tensor = base_tensors[index]
                positive_image_index, positive_tensor = base_tensors[index+1]
                image_tensors.append(anchor_tensor)
                image_tensors.append(positive_tensor)
                if is_training:
                    vector_indices.append(training_image_to_vector_index[(base_filename, anchor_image_index)])
                    vector_indices.append(training_image_to_vector_index[(base_filename, positive_image_index)])
                # 如果是训练集，则计算基础图片的编码与其他编码的距离
                nearest_indices = []
                if is_training:
                    vector_index = training_image_to_vector_index[(base_filename, anchor_image_index)]
                    if vector_index in calculated_index_set:
                        nearest_indices = ((training_vectors_calculated -
                            training_vectors[vector_index]).abs().sum(dim=1).sort().indices).tolist()
                # 选取负样本
                # 如果是训练集则选取编码最接近的样本+随机样本作为负样本
                # 如果是验证集和测试集则随机选取样本
                if is_training and nearest_indices:
                    negative_samples = NEGATIVE_SAMPLES - NEGATIVE_RANDOM_SAMPLES
                    negative_random_samples = NEGATIVE_RANDOM_SAMPLES
                else:
                    negative_samples = 0
                    negative_random_samples = NEGATIVE_SAMPLES
                negative_skip_nearest = NEGATIVE_SKIP_NEAREST
                for calculated_index in nearest_indices:
                    if negative_samples <= 0:
                        break
                    filename, image_index = calculated_index_to_image[calculated_index]
                    if filename == base_filename:
                        continue # 跳过同一人物
                    if negative_skip_nearest > 0:
                        negative_skip_nearest -= 1
                        continue # 跳过非常相似的人物
                    target_tensor = load_tensor(os.path.join("data", filename))
                    # 添加负样本到列表
                    image_tensors.append(target_tensor[image_index])
                    if is_training:
                        vector_indices.append(training_image_to_vector_index[(filename, image_index)])
                    negative_samples -= 1
                while negative_random_samples > 0:
                    file_index = random.randint(0, len(dataset_multiple) + len(dataset_single) - 1)
                    if file_index < len(dataset_multiple):
                        filename = dataset_multiple[file_index]
                    else:
                        filename = dataset_single[file_index - len(dataset_multiple)]
                    if filename == base_filename:
                        continue # 跳过同一人物
                    target_tensor = load_tensor(os.path.join("data", filename))
                    image_index = random.randint(0, target_tensor.shape[0] - 1)
                    # 添加负样本到列表
                    image_tensors.append(target_tensor[image_index])
                    if is_training:
                        vector_indices.append(training_image_to_vector_index[(filename, image_index)])
                    negative_random_samples -= 1
                assert negative_samples == 0
                assert negative_random_samples == 0
                # 如果图片数量大于批次大小，则返回批次
                if len(image_tensors) >= batch_size:
                    yield torch.stack(image_tensors).to(device), vector_indices
                    image_tensors.clear()
                    vector_indices.clear()
        if image_tensors:
            yield torch.stack(image_tensors).to(device), vector_indices

    # 开始训练过程
    for epoch in range(0, 200):
        print(f"epoch: {epoch}")

        # 根据训练集训练并修改参数
        # 切换模型到训练模式
        model.train()
        training_accuracy_list = []
        for index, (batch_x, vector_indices) in enumerate(
            generate_inputs(training_set, training_set_single, 400)):
            # 计算预测值
            predicted = model(batch_x)
            # 计算损失
            loss = loss_function(predicted)
            # 从损失自动微分求导函数值
            loss.backward()
            # 使用参数调整器调整参数
            optimizer.step()
            # 清空导函数值
            optimizer.zero_grad()
            # 记录各个人物的编码
            for vector_index, vector in zip(vector_indices, predicted):
                # 复制回 cpu 并去掉用于自动微分的计算路径信息
                training_vectors[vector_index] = vector.to("cpu").detach()
                training_vectors_calculated_indices.add(vector_index)
            # 记录这一个批次的正确率，torch.no_grad 代表临时禁用自动微分功能
            with torch.no_grad():
                training_batch_accuracy = calc_accuracy(predicted)
            # 输出批次正确率
            training_accuracy_list.append(training_batch_accuracy)
            print(f"epoch: {epoch}, batch: {index}, accuracy: {training_batch_accuracy}")
        training_accuracy = sum(training_accuracy_list) / len(training_accuracy_list)
        training_accuracy_history.append(training_accuracy)
        print(f"training accuracy: {training_accuracy}")

        # 检查验证集
        # 切换模型到验证模式
        model.eval()
        validating_accuracy_list = []
        for batch_x, _ in generate_inputs(validating_set, validating_set_single, 100):
            predicted = model(batch_x)
            validating_batch_accuracy = calc_accuracy(predicted)
            validating_accuracy_list.append(validating_batch_accuracy)
            # 释放 predicted 占用的显存避免显存不足的错误
            predicted = None
        validating_accuracy = sum(validating_accuracy_list) / len(validating_accuracy_list)
        validating_accuracy_history.append(validating_accuracy)
        print(f"validating accuracy: {validating_accuracy}")

        # 记录最高的验证集正确率与当时的模型状态，判断是否在多次训练后仍然没有刷新记录
        # 因为验证集的负样本是随机选择的，允许 1% 的波动使得模型可以训练更多次
        if (validating_accuracy + 0.01) > validating_accuracy_highest:
            if validating_accuracy > validating_accuracy_highest:
                validating_accuracy_highest = validating_accuracy
                print("highest validating accuracy updated")
            else:
                print("highest validating accuracy not dropped")
            validating_accuracy_highest_epoch = epoch
            save_tensor(model.state_dict(), "model.recognition.pt")
        elif epoch - validating_accuracy_highest_epoch > 20:
            # 在多次训练后仍然没有刷新记录，结束训练
            print("stop training because validating accuracy dropped from highest in 20 epoches")
            break

    # 使用达到最高正确率时的模型状态
    print(f"highest validating accuracy: {validating_accuracy_highest}",
        f"from epoch {validating_accuracy_highest_epoch}")
    model.load_state_dict(load_tensor("model.recognition.pt"))

    # 检查测试集
    testing_accuracy_list = []
    for batch_x, _ in generate_inputs(testing_set, testing_set_single, 100):
        predicted = model(batch_x)
        testing_batch_accuracy = calc_accuracy(predicted)
        testing_accuracy_list.append(testing_batch_accuracy)
    testing_accuracy = sum(testing_accuracy_list) / len(testing_accuracy_list)
    print(f"testing accuracy: {testing_accuracy}")

    # 显示训练集和验证集的正确率变化
    pyplot.plot(training_accuracy_history, label="training_accuracy")
    pyplot.plot(validating_accuracy_history, label="validating_accuracy")
    pyplot.ylim(0, 1)
    pyplot.legend()
    pyplot.show()

def train_verify():
    """开始训练人脸认证模型"""
    # 创建人脸识别模型实例并加载训练好的参数
    recognize_model = FaceRecognitionModel().to(device)
    recognize_model.load_state_dict(load_tensor("model.recognition.pt"))
    recognize_model.eval()

    # 创建人脸认证模型实例
    model = FaceVerificationModel().to(device)

    # 创建损失计算器
    loss_function = model.loss_function

    # 创建参数调整器
    optimizer = torch.optim.Adam(model.parameters())

    # 记录训练集和验证集的正确率变化
    training_accuracy_history = []
    validating_accuracy_history = []

    # 记录最高的验证集正确率
    validating_accuracy_highest = -1
    validating_accuracy_highest_epoch = 0

    # 计算正确率的工具函数
    calc_accuracy = model.calc_accuracy

    # 读取人物列表，区分图片数量足够的人物和图片数量不足的人物
    # 图片数量不足的人物会作为负样本使用
    filenames = os.listdir("data")
    multiple_samples = []
    single_samples = []
    for filename in filenames:
        if int(filename.split('.')[-2]) >= MINIMAL_POSITIVE_SAMPLES:
            multiple_samples.append(filename)
        else:
            single_samples.append(filename)
    random.seed(123) # 让这里的顺序跟训练人脸识别模型时的顺序不一样
    random.shuffle(multiple_samples)
    random.shuffle(single_samples)
    total_multiple_samples = len(multiple_samples)
    total_single_samples = len(single_samples)

    # 分割训练集 (80%)，验证集 (10%) 和测试集 (10%)
    training_set = multiple_samples[:int(total_multiple_samples*0.8)]
    training_set_single = single_samples[:int(total_single_samples*0.8)]
    validating_set = multiple_samples[int(total_multiple_samples*0.8):int(total_multiple_samples*0.9)]
    validating_set_single = single_samples[int(total_single_samples*0.8):int(total_single_samples*0.9)]
    testing_set = multiple_samples[int(total_multiple_samples*0.9):]
    testing_set_single = single_samples[int(total_single_samples*0.9):]

    # 编码的缓存 { (文件名,索引值): 编码 }
    vector_cache = {}

    # 根据图片获取编码
    def get_vector(filename, image_index, image_tensor):
        key = (filename, image_index)
        vector = vector_cache.get(key)
        if vector is None:
            with torch.no_grad():
                vector = recognize_model(image_tensor.unsqueeze(0).to(device))[0].to("cpu")
            vector_cache[key] = vector
        return vector

    # 生成用于训练的输入
    # 返回 [ 同一人物编码的差异, 不同人物编码的差异, ... ]
    def generate_inputs(dataset_multiple, dataset_single, batch_size):
        # 枚举数据集，会重复 REPEAT_SAMPLES 次以减少随机选择导致的正确率浮动
        diff_tensors = []
        for base_filename in dataset_multiple * REPEAT_SAMPLES:
            # 读取基础人物的图片
            base_tensor = load_tensor(os.path.join("data", base_filename))
            base_tensors = list(enumerate(base_tensor))
            # 打乱顺序，然后两张两张图片的选取基础图片和正样本
            random.shuffle(base_tensors)
            for index in range(0, len(base_tensors)-1, 2):
                # 计算基础图片和正样本的编码差异并添加到列表
                anchor_image_index, anchor_tensor = base_tensors[index]
                positive_image_index, positive_tensor = base_tensors[index+1]
                anchor_vector = get_vector(base_filename, anchor_image_index, anchor_tensor)
                positive_vector = get_vector(base_filename, positive_image_index, positive_tensor)
                diff_tensors.append((anchor_vector - positive_vector).pow(2))
                # 随机选取负样本，计算差异并添加到列表
                negative_random_samples = NEGATIVE_SAMPLES
                while negative_random_samples > 0:
                    file_index = random.randint(0, len(dataset_multiple) + len(dataset_single) - 1)
                    if file_index < len(dataset_multiple):
                        filename = dataset_multiple[file_index]
                    else:
                        filename = dataset_single[file_index - len(dataset_multiple)]
                    if filename == base_filename:
                        continue # 跳过同一人物
                    target_tensor = load_tensor(os.path.join("data", filename))
                    image_index = random.randint(0, target_tensor.shape[0] - 1)
                    negative_vector = get_vector(filename, image_index, target_tensor[image_index])
                    diff_tensors.append((anchor_vector - negative_vector).pow(2))
                    negative_random_samples -= 1
                # 如果差异数量大于批次大小，则返回批次
                if len(diff_tensors) >= batch_size:
                    yield torch.stack(diff_tensors).to(device)
                    diff_tensors.clear()
        if diff_tensors:
            yield torch.stack(diff_tensors).to(device)

    # 开始训练过程
    for epoch in range(1, 20):
        print(f"epoch: {epoch}")

        # 根据训练集训练并修改参数
        # 切换模型到训练模式
        model.train()
        training_accuracy_list = []
        for index, batch_x in enumerate(
            generate_inputs(training_set, training_set_single, 400)):
            # 计算预测值
            predicted = model(batch_x)
            # 计算损失
            loss = loss_function(predicted)
            # 从损失自动微分求导函数值
            loss.backward()
            # 使用参数调整器调整参数
            optimizer.step()
            # 清空导函数值
            optimizer.zero_grad()
            # 记录这一个批次的正确率，torch.no_grad 代表临时禁用自动微分功能
            with torch.no_grad():
                training_batch_accuracy = calc_accuracy(predicted)
            # 输出批次正确率
            training_accuracy_list.append(training_batch_accuracy)
            print(f"epoch: {epoch}, batch: {index}, accuracy: {training_batch_accuracy}")
        training_accuracy = sum(training_accuracy_list) / len(training_accuracy_list)
        training_accuracy_history.append(training_accuracy)
        print(f"training accuracy: {training_accuracy}")

        # 检查验证集
        # 切换模型到验证模式
        model.eval()
        validating_accuracy_list = []
        for batch_x in generate_inputs(validating_set, validating_set_single, 100):
            predicted = model(batch_x)
            validating_batch_accuracy = calc_accuracy(predicted)
            validating_accuracy_list.append(validating_batch_accuracy)
            # 释放 predicted 占用的显存避免显存不足的错误
            predicted = None
        validating_accuracy = sum(validating_accuracy_list) / len(validating_accuracy_list)
        validating_accuracy_history.append(validating_accuracy)
        print(f"validating accuracy: {validating_accuracy}")

        # 记录最高的验证集正确率与当时的模型状态，判断是否在多次训练后仍然没有刷新记录
        # 因为验证集的负样本是随机选择的，允许 1% 的波动使得模型可以训练更多次
        if (validating_accuracy + 0.01) > validating_accuracy_highest:
            if validating_accuracy > validating_accuracy_highest:
                validating_accuracy_highest = validating_accuracy
                print("highest validating accuracy updated")
            else:
                print("highest validating accuracy not dropped")
            validating_accuracy_highest_epoch = epoch
            save_tensor(model.state_dict(), "model.verification.pt")
        elif epoch - validating_accuracy_highest_epoch > 20:
            # 在多次训练后仍然没有刷新记录，结束训练
            print("stop training because validating accuracy dropped from highest in 20 epoches")
            break

    # 使用达到最高正确率时的模型状态
    print(f"highest validating accuracy: {validating_accuracy_highest}",
        f"from epoch {validating_accuracy_highest_epoch}")
    model.load_state_dict(load_tensor("model.verification.pt"))

    # 检查测试集
    testing_accuracy_list = []
    for batch_x in generate_inputs(testing_set, testing_set_single, 100):
        predicted = model(batch_x)
        testing_batch_accuracy = calc_accuracy(predicted)
        testing_accuracy_list.append(testing_batch_accuracy)
    testing_accuracy = sum(testing_accuracy_list) / len(testing_accuracy_list)
    print(f"testing accuracy: {testing_accuracy}")

    # 显示训练集和验证集的正确率变化
    pyplot.plot(training_accuracy_history, label="training_accuracy")
    pyplot.plot(validating_accuracy_history, label="validating_accuracy")
    pyplot.ylim(0, 1)
    pyplot.legend()
    pyplot.show()

def main():
    """主函数"""
    if len(sys.argv) < 2:
        print(f"Please run: {sys.argv[0]} prepare|train")
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
    elif operation == "train-verify":
        train_verify()
    else:
        raise ValueError(f"Unsupported operation: {operation}")

if __name__ == "__main__":
    main()
```

以下是一些实现上的细节。

- 因为图片数量不多，在处理图片之前会先转换到黑白图片和缩放到 80x80 以避免过拟合，如果图片数量足够可以不需要转换到黑白和使用更高的像素值
- 跟 Facenet 论文不一样，这个实现会全局查找不同人物但编码距离最接近的人脸，同时跳过前 20 个人脸
- 跟 Facenet 论文一样，这个实现的编码长度是 32，要求不同人物的距离是 0.2
- 这个实现选择人物的时候不会只选择 3 张图片，而是选择 1 张基础图片，1 张正样本图片 (同一个人) 和 10 张负样本图片 (不同的人)，这样可以让计算速度更快
- 人脸识别模型的正确率会依据选取的"基础图片和正样本图片的编码距离"是否小于"基础图片和所有负样本图片的编码距离"计算
- 因为随机选择会导致验证集正确率浮动，这里会允许最高正确率浮动 1%，并且最多训练次数会有比较低的限制

把代码保存到 face_recognition.py，然后按以下文件夹结构存放：

- face-recognition
    - dataset
        - 105_classes_pins_dataset
        - face-recognition-dataset
            - Faces
        - lfwpeople
            - lfw_funneled
    - face_recognition.py

再执行以下命令即可训练人脸识别模型：

``` text
python3 face_recognition.py prepare
python3 face_recognition.py train
```

最终输出结果如下，大概 83%~85% 的最接近的人脸是同一个人🤒：

``` text
epoch: 199, batch: 646, accuracy: 1.0
epoch: 199, batch: 647, accuracy: 1.0
epoch: 199, batch: 648, accuracy: 1.0
training accuracy: 0.9798332275899607
validating accuracy: 0.8293447293447292
highest validating accuracy updated
highest validating accuracy: 0.8293447293447292 from epoch 199
testing accuracy: 0.8504521963824275
```

接下来再执行以下命令即可训练人脸认证模型：

``` text
python3 face_recognition.py train-verify
```

最终输出结果如下，令人吃惊的是识别是否同一个人的精度达到了 96%~97% (这还是正负样本正确率分别计算再平均后的值)，这说明了即使欧几里德距离最接近也不一定是同一个人，人脸认证模型给各项指标分配不同的系数来计算是有一定效果的。后面我们应用模型的时候，会先选取最接近的 N 张人脸，再使用人脸认证模型来一个个判断是否同一个人。

``` text
epoch: 19, batch: 569, accuracy: 0.9283783783783783
epoch: 19, batch: 570, accuracy: 0.9567567567567568
epoch: 19, batch: 571, accuracy: 0.9304347826086956
training accuracy: 0.9617334193421163
validating accuracy: 0.9590857605178013
highest validating accuracy not dropped
highest validating accuracy: 0.9623381877022668 from epoch 19
testing accuracy: 0.9714264705882371
```

和之前几篇文章不一样的是，这份代码没有给出 `eval_model` 函数，这是因为人脸图片通常都需要经过预处理，不会直接交给模型使用。下面将会介绍如何结合 faster-rcnn 模型检测图片中的人脸，再根据上一篇文章介绍的脸部关键点检测模型调整人脸范围，最后截取人脸交给人脸识别模型和人脸认证模型。

## 结合前几篇的模型实现人脸检测 + 识别

假设我们想识别某张图片上的人是谁，组合本文介绍的模型和前几篇文章介绍的模型即可得出以下的流程：

![09](./09.png)

首先我们把三个模型的代码和训练好的参数文件 (model.pt) 按以下结构存放

- faster-rcnn
    - fasterrcnn.py: 来源在[这里](https://www.cnblogs.com/zkweb/p/14235259.html)
    - model.pt: 可以到[这里](https://github.com/303248153/BlogArchive/releases/tag/202001)下载，下载后需要重命名 (`faster-rcnn-10.5-model.pt`
 => `model.pt`)
- face-landmark
    - face_landmark.py: 来源在[这里](https://www.cnblogs.com/zkweb/p/14510884.html)
    - model.pt: 可以到[这里](TODO)下载，下载后需要重命名 (`face-landmark-model.pt` => `model.pt`)
- face-recognition
    - face_recognition.py: 来源在这篇文章的上面
    - model.recognition.pt: 可以到[这里](TODO)下载，下载后需要重命名 (`face-recognition-model.recognition.pt` => `model.recognition.pt`)
    - model.verification.pt: 可以到[这里](TODO)下载，下载后需要重命名 (`face-recognition-model.verification.pt` => `model.verification.pt`)

之后我们需要准备构建人脸编码数据库的人脸，也就是识别的对象，这里我为了方便测试收集了一些中国领导人的照片 (这是首先让模型认领导😤)，可以到[这里](https://github.com/303248153/BlogArchive/tree/master/ml-13/face_recognition_samples)下载。

然后就是结合这些模型的代码了：

``` python
import sys
import os
import torch
from collections import defaultdict
from PIL import Image, ImageDraw, ImageFont

# 加载模型所在的模块
sys.path.append("../face-landmark")
sys.path.append("../face-recognition")
import fasterrcnn
import face_landmark
import face_recognition

# 构建编码数据库使用的文件夹
# 要求图片路径是 {SAMPLES_DIR}/{人物名称}/图片名
SAMPLES_DIR = "./face_recognition_samples"

# 输出人脸图片使用的文件夹
FACES_OUTPUT_DIR = "./detected_faces"

# 编码数据库的保存路径
# 如果需要重新构建请删除此文件
VECTORS_PATH = "./face_recognition_vectors.pt"

# 使用关键点调整脸部范围的次数
ADJUST_FACE_REGION_BY_LANDMARK_TIMES = 3

# 脸部范围相对关键点范围的比例
FACE_REGION_RATIO_BY_LANDMARK = 3.0

# 判断是同一人物需要的分数阈值
FACE_VERIFICATION_THRESHOLD = 0.92

# 用于启用 GPU 支持
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

def adjust_face_region(image, region, face_landmark_model):
    """使用关键点调整脸部范围"""
    x, y, w, h = region
    child_img = image.crop((x, y, x+w, y+h))
    points = []
    for _ in range(ADJUST_FACE_REGION_BY_LANDMARK_TIMES):
        points = face_landmark_model.detect_landmarks([child_img])[0]
        min_x = min(p[0] for p in points)
        min_y = min(p[1] for p in points)
        max_x = max(p[0] for p in points)
        max_y = max(p[1] for p in points)
        landmark_w = max_x - min_x
        landmark_h = max_y - min_y
        center_x = min_x + landmark_w * 0.5 + x
        center_y = min_y + landmark_h * 0.5 + y
        radius = max(landmark_w, landmark_h) * FACE_REGION_RATIO_BY_LANDMARK / 2
        x0 = int(min(max(center_x - radius, 0), image.size[0]-1))
        x1 = int(min(max(center_x + radius, 0), image.size[0]-1))
        y0 = int(min(max(center_y - radius, 0), image.size[1]-1))
        y1 = int(min(max(center_y + radius, 0), image.size[1]-1))
        x_diff = x0 - x
        y_diff = y0 - y
        x, y, w, h = x0, y0, x1-x0, y1-y0
        points = [ (px - x_diff, py - y_diff) for px, py in points ]
        if w == 0 or h == 0:
            # 检测关键点失败，返回原始范围
            return child_img, region, []
        child_img = image.crop((x, y, x+w, y+h))
    return child_img, (x, y, w, h), points

def build_vectors(faster_rcnn_model, face_landmark_model, face_recognition_model):
    """根据人物和图片构建编码数据库"""
    print("building face recognition vectors from samples")
    names = []
    images = []
    result_names = []
    result_vectors = []
    batch_size = 10
    def process_images():
        # 查找人脸区域
        tensor_in = torch.stack([
            fasterrcnn.image_to_tensor(fasterrcnn.resize_image(img))
            for img in images
        ]).to(device)
        cls_result = faster_rcnn_model(tensor_in)[-1]
        # 截取各图片中的人脸区域
        face_names = []
        face_images = []
        for name, image, result in zip(names, images, cls_result):
            if not result:
                print("no face found for", name)
                continue
            result = fasterrcnn.MyModel.merge_predicted_result(result)
            # 按分数排序并选取分数最高的区域
            result.sort(key=lambda r: -r[2])
            label, box, rpn_score, cls_score = result[0]
            x, y, w, h = fasterrcnn.map_box_to_original_image(box, *image.size)
            if w == 0 or h == 0:
                print("no face found for", name, "due to incorrect size")
                continue
            # 使用脸部关键点调整脸部范围
            child_img, _, points = adjust_face_region(image, (x, y, w, h), face_landmark_model)
            # 保存检测结果用于调试
            if not os.path.isdir(FACES_OUTPUT_DIR):
                os.makedirs(FACES_OUTPUT_DIR)
            face_landmark.draw_points(child_img, points)
            child_img.convert("RGB").save(os.path.join(
                FACES_OUTPUT_DIR, f"{name[0]}_{os.path.splitext(name[1])[0]}.png"))
            face_names.append(name)
            face_images.append(child_img)
        # 转换人脸图片到编码
        tensor_in = torch.stack([
            face_recognition.image_to_tensor(face_recognition.resize_image(img))
            for img in face_images
        ]).to(device)
        face_vectors = face_recognition_model(tensor_in)
        # 添加名称和编码到结果列表
        for name in face_names:
            result_names.append(name)
        result_vectors.append(face_vectors)
        names.clear()
        images.clear()
    for dirname in os.listdir(SAMPLES_DIR):
        dirpath = os.path.join(SAMPLES_DIR, dirname)
        if not os.path.isdir(dirpath):
            continue
        for filename in os.listdir(dirpath):
            if os.path.splitext(filename)[1].lower() not in (".jpg", ".png"):
                continue
            names.append((dirname, filename))
            images.append(Image.open(os.path.join(dirpath, filename)))
            if len(images) >= batch_size:
                process_images()
    if images:
        process_images()
    # 整合编码列表
    result_vector = torch.cat(result_vectors, dim=0)
    # 保存名称和编码
    fasterrcnn.save_tensor((result_names, result_vector), VECTORS_PATH)
    peoples_count = len(set(n[0] for n in result_names))
    print(f"built vectors for {peoples_count} peoples and {result_vector.shape[0]} images")

def recognize_face(
    faster_rcnn_model, face_landmark_model,
    face_recognition_model, face_verification_model,
    image, vectors, top_range=10):
    """识别人脸位置与身份"""
    # 查找人脸区域
    tensor_in = fasterrcnn.image_to_tensor(
        fasterrcnn.resize_image(image)).unsqueeze(0).to(device)
    cls_result = faster_rcnn_model(tensor_in)[-1]
    # 按分数排序并选取分数最高的区域
    result = cls_result[0]
    if not result:
        return None
    result = fasterrcnn.MyModel.merge_predicted_result(result)
    result.sort(key=lambda r: -r[2])
    label, box, rpn_score, cls_score = result[0]
    x, y, w, h = fasterrcnn.map_box_to_original_image(box, *image.size)
    if w == 0 or h == 0:
        return None
    # 使用脸部关键点调整脸部范围
    child_img, (x, y, w, h), points = adjust_face_region(
        image, (x, y, w, h), face_landmark_model)
    # 生成人脸编码
    tensor_in = face_recognition.image_to_tensor(
        face_recognition.resize_image(child_img)).unsqueeze(0).to(device)
    vector = face_recognition_model(tensor_in)[0]
    # 比较人脸编码，得出最接近的 N 张人脸
    diff = (vector - vectors).pow(2)
    diff_sorted = diff.sum(dim=1).sort()
    indices = diff_sorted.indices[:top_range].tolist()
    # 使用人脸认证模型匹配人脸，身份不明时返回 None
    highest_score = None
    highest_index = None
    scores = face_verification_model(diff[indices]).tolist()
    for index, score in zip(indices, scores):
        if score < FACE_VERIFICATION_THRESHOLD:
            continue
        if highest_score and score <= highest_score:
            continue
        highest_index = index
        highest_score = score
    # 返回人脸图片，人脸范围，人脸关键点，匹配出来的身份，分数
    # 没有匹配到身份时，身份和分数会为 None
    return child_img, (x, y, w, h), points, highest_index, highest_score

def main():
    """使用 fasterrcnn + facenet 实现人脸识别"""
    # 让 fasterrcnn 合并区域时不使用 NMS 算法，使得结果区域更大
    fasterrcnn.USE_NMS_ALGORITHM = False

    # 加载 fasterrcnn 模型
    faster_rcnn_model = fasterrcnn.MyModel().to(device)
    faster_rcnn_model.load_state_dict(fasterrcnn.load_tensor("model.pt"))
    faster_rcnn_model.eval()

    # 加载人脸关键点识别模型
    face_landmark_model = face_landmark.FaceLandmarkModel().to(device)
    face_landmark_model.load_state_dict(fasterrcnn.load_tensor("../face-landmark/model.pt"))
    face_landmark_model.eval()

    # 加载人脸识别模型
    face_recognition_model = face_recognition.FaceRecognitionModel().to(device)
    face_recognition_model.load_state_dict(face_recognition.load_tensor("../face-recognition/model.recognition.pt"))
    face_recognition_model.eval()

    # 加载人脸验证模型
    face_verification_model = face_recognition.FaceVerificationModel().to(device)
    face_verification_model.load_state_dict(face_recognition.load_tensor("../face-recognition/model.verification.pt"))
    face_verification_model.eval()

    # 根据人物和图片构建编码数据库
    if not os.path.isfile(VECTORS_PATH):
        build_vectors(faster_rcnn_model, face_landmark_model, face_recognition_model)

    # 读取编码数据库
    names, vectors = fasterrcnn.load_tensor(VECTORS_PATH)

    # 询问图片路径，并识别人脸
    font = ImageFont.truetype("wqy-microhei.ttc", 20)
    while True:
        try:
            # 打开图片
            image_path = input("Image path: ")
            if not image_path:
                continue
            image = Image.open(image_path)
            # 识别人脸
            result = recognize_face(
                faster_rcnn_model, face_landmark_model,
                face_recognition_model, face_verification_model, image, vectors)
            if not result:
                print("no face found\n")
                continue
            # 根据结果标记到图片上
            child_img, (x, y, w, h), points, index, score = result
            points = [ (px + x, py + y) for px, py in points ]
            label = f"{names[index][0]}: {score:.2f}" if index else "Unknown"
            print("result:", label)
            color = "#FF0000"
            draw = ImageDraw.Draw(image)
            draw.rectangle((x, y, x+w, y+h), outline=color, width=3)
            draw.text((x, y-20), label, fill=color, font=font)
            face_landmark.draw_points(image, points)
            image.save("img_output.png")
            print("saved to img_output.png")
            print()
        except Exception as e:
            print("error:", e)

if __name__ == "__main__":
    main()
```

使用脸部关键点调整脸部范围的代码在 `adjust_face_region` 函数中，构建人物编码数据库的代码在 `build_vectors` 函数中，而识别人脸的代码在 `recognize_face` 函数中。

把代码和人物图片按以下的文件夹结构保存：

- faster-rcnn
    - face_recognition_samples
        - 人物名称
            - 图片1.jpg
            - 图片2.jpg
        - 人物名称
            - 图片1.jpg
            - 图片2.jpg
            - 图片3.jpg
    - fasterrcnn.py
    - fasterrcnn_face_recognition.py (上面给出的代码)
    - model.pt
- face-landmark
    - face_landmark.py
    - model.pt
- face-recognition
    - face_recognition.py
    - model.recognition.pt
    - model.verification.pt

然后再执行以下命令即可尝试人脸识别功能：

``` text
cd faster-rcnn
python3 fasterrcnn_face_recognition.py
```

首次运行的时候会根据 face_recognition_samples 文件夹下的人物构建编码数据库，如果想重新构建可以删掉 `face_recognition_vectors.pt` 再运行。

以下是部分识别结果：

![img_output1.png](./img_output1.png)
![img_output2.png](./img_output2.png)
![img_output3.png](./img_output3.png)
![img_output4.png](./img_output4.png)
![img_output5.png](./img_output5.png)
![img_output6.png](./img_output6.png)

不在数据库的人物的识别结果：

![img_output_unknown1.png](./img_output_unknown1.png)
![img_output_unknown2.png](./img_output_unknown2.png)

经过试验精度还是不错的😤。

本篇文章介绍的模型可以用在考勤，访客管理等系统中，但不应该用于支付和解锁，支付和解锁使用的人脸识别模型要求精度更高，并且很大可能要求构建三维模型而不是简单的识别图片🤧。此外，识别逃犯反而不要求太高的准确度，因为逃犯通常会打扮的和数据库中的照片不一样，只要识别出可疑人物即可通知警察人工判断，如果真的看上去是同一个人，就可以跟踪抓捕了😡。

## 写在最后

这个系列预计再写一两篇就会发目录给出版社，到时候也会重新编排内容让学习更加简单，继续等等吧🤕。

此外，我准备开拓一个新的系列介绍 SciSharp 的 [TensorFlow.NET](https://github.com/SciSharp/TensorFlow.NET)，定位同样是入门，主要面向没有 Python 基础的 .NET 教徒，敬请期待叭😎。