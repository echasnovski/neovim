describe('vim.pack', function()
  describe('add()', function()
    pending('works', function()
      -- TODO
    end)

    pending('normalizes each spec', function() end)

    pending('normalizes spec array', function()
      -- TODO
      -- Should silently ignore full duplicates (same `source`+`version`)
      -- and error on conflicts.
    end)
  end)

  describe('update()', function()
    pending('works', function()
      -- TODO
    end)
  end)

  describe('get()', function()
    pending('works', function()
      -- TODO
    end)

    pending('works after `del()`', function()
      -- TODO: Should not include removed plugins and still return list

      -- TODO: Should return corrent list inside `PackDelete` event
    end)
  end)

  describe('del()', function()
    pending('works', function()
      -- TODO
    end)
  end)
end)
