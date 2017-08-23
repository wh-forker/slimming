--
--  Copyright (c) 2016, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
require 'torch'
require 'paths'
require 'optim'
require 'nn'
require 'saveTXT'
require 'cutorch'
local DataLoader = require 'dataloader'
local models = require 'models/init'
local Trainer = require 'train_bn'
local opts = require 'opts'
local checkpoints = require 'checkpoints'

torch.setdefaulttensortype('torch.FloatTensor')
torch.setnumthreads(1)

local opt = opts.parse(arg)
torch.manualSeed(opt.manualSeed)
cutorch.manualSeedAll(opt.manualSeed)
-- cutorch.setDevice(4)
-- Load previous checkpoint, if it exists
local checkpoint, optimState = checkpoints.latest(opt)

-- Create model
local model, criterion = models.setup(opt, checkpoint)

-- Data loading
local trainLoader, valLoader = DataLoader.create(opt)

-- The trainer handles the training loop and evaluation on validation set
local trainer = Trainer(model, criterion, opt, optimState)

-- size = trainer.model:getParameters():size()
-- size = p:size()[1]
all_results = {}

-- print(trainer.model)
-- print("parameters:"..size)

if opt.testOnly then
   for i = 1, 30 do
      local top1Err, top5Err = trainer:test(0, valLoader)
   end
   print(string.format(' * Results top1: %6.3f  top5: %6.3f', top1Err, top5Err))
   all_results = {{top1Err, top5Err}}
   save2txt(opt.retrain, all_results)
   return
end

local startEpoch = checkpoint and checkpoint.epoch + 1 or opt.epochNumber
local bestTop1 = math.huge
local bestTop5 = math.huge
for epoch = startEpoch, opt.nEpochs do
   -- Train for a single epoch
   local trainTop1, trainTop5, trainLoss = trainer:train(epoch, trainLoader)

   -- Run model on validation set
   local testTop1, testTop5 = trainer:test(epoch, valLoader)

   local bestModel = false
   if testTop1 < bestTop1 then
      bestModel = true
      bestTop1 = testTop1
      bestTop5 = testTop5
      print(' * Best model ', testTop1, testTop5)
   end

   checkpoints.save(epoch, model, trainer.optimState, bestModel, opt)

   all_results[#all_results+1] = {testTop1, trainTop1, trainLoss}
   local filename = string.format('%s/%s_%d_%d_%d', 
      opt.save,opt.dataset,opt.nEpochs, opt.depth, 12)
   save2txt(filename, all_results)
end
-- checkpoints.save(epoch, model, trainer.optimState, bestModel, opt)


print(string.format(' * Finished top1: %6.3f  top5: %6.3f', bestTop1, bestTop5))